// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IDSCEngine} from "./IDSCEngine.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author Nikolay P. Ivanov
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */
contract DSCEngine is IDSCEngine, ReentrancyGuard {
    ///////////////////
    // Errors
    ///////////////////
    error DSCEngine__NeedsMoreThanZeroAmount();
    error DSCEngine__TokenAddressesAndPriceFeedsLengthDoNotMatch();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TokenTransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    ///////////////////
    // State Variables
    ///////////////////
    DecentralizedStableCoin private i_dsc;

    uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means you need to be 200% over-collateralized
    uint256 private constant LIQUIDATION_BONUS = 10; // This means you get assets at a 10% discount when liquidating
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;

    /// @dev Mapping of token address to price feed address
    mapping(address collateralToken => address priceFeed) private s_priceFeeds;
    /// @dev Amount of collateral deposited by user
    mapping(address user => mapping(address collateralToken => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_dscMinted;

    address[] private s_collateralTokens;

    ///////////////////
    // Events
    ///////////////////

    event CollateralDeposited(address indexed user, address indexed collateralToken, uint256 amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed collateralToken, uint256 amount);

    ///////////////////
    // Modifiers
    ///////////////////

    modifier nonZeroAmount(uint256 _amount) {
        if (_amount == 0) revert DSCEngine__NeedsMoreThanZeroAmount();
        _;
    }

    modifier notUnsupportedToken(address _tokenCollateralAddress) {
        if (s_priceFeeds[_tokenCollateralAddress] == address(0)) revert DSCEngine__NotAllowedToken();
        _;
    }

    ///////////////////
    // Functions
    ///////////////////

    constructor(address[] memory _tokenAddresses, address[] memory _priceFeedAddresses, address dscAddress) {
        if (_tokenAddresses.length != _priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedsLengthDoNotMatch();
        }

        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            s_priceFeeds[_tokenAddresses[i]] = _priceFeedAddresses[i];
            s_collateralTokens.push(_tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ///////////////////
    // External Functions
    ///////////////////

    /**
     * @notice Follows CEI pattern
     * @inheritdoc IDSCEngine
     */
    function depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral)
        external
        override
        nonZeroAmount(_amountCollateral)
        notUnsupportedToken(_tokenCollateralAddress)
        nonReentrant
    {
        _depositCollateral(_tokenCollateralAddress, _amountCollateral);
    }

    /**
     * @notice Deposit collateral and mint DSC
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of tokenCollateral to deposit
     * @param amountDsc The amount of DSC to mint
     */
    function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDsc)
        external
        override
        nonZeroAmount(amountCollateral)
        nonZeroAmount(amountDsc)
        notUnsupportedToken(tokenCollateralAddress)
        nonReentrant
    {
        _depositCollateral(tokenCollateralAddress, amountCollateral);
        _mintDsc(amountDsc);
    }

    function redeemCollateral(address tokenCollateral, uint256 amount)
        external
        override
        nonZeroAmount(amount)
        notUnsupportedToken(tokenCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateral, amount, msg.sender, msg.sender);
    }

    function burnDsc(uint256 amount) external override nonZeroAmount(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
    }

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're withdrawing
     * @param amountCollateral: The amount of collateral you're withdrawing
     * @param amountDscToBurn: The amount of DSC you want to burn
     * @notice This function will withdraw your collateral and burn DSC in one transaction
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
        nonZeroAmount(amountCollateral)
        nonZeroAmount(amountDscToBurn)
        notUnsupportedToken(tokenCollateralAddress)
    {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
    }

    /**
     * @notice Liquidate a user
     * @param collateral The collateral token address
     * @param user The user to liquidate
     * @param debt The debt to liquidate
     * @notice You can partially liquidate a user.
     * @notice You will get a 10% LIQUIDATION_BONUS for taking the users funds.
     * @notice This function working assumes that the protocol will be roughly 150% overcollateralized in order for this to work.
     * @notice A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate anyone.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     */
    function liquidate(address collateral, address user, uint256 debt)
        external
        override
        nonZeroAmount(debt)
        notUnsupportedToken(collateral)
        nonReentrant
    {
        uint256 startingHealthFactor = _healthFactor(user);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) revert DSCEngine__HealthFactorOk();

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debt);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        _redeemCollateral(collateral, tokenAmountFromDebtCovered + bonusCollateral, user, msg.sender);
        _burnDsc(debt, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactory() external view override {}

    /**
     * @notice Check if the collateral value > DSC amount
     * @notice They must have more collateral value
     */
    function mintDsc(uint256 amount) external override nonZeroAmount(amount) nonReentrant {
        _mintDsc(amount);
    }

    ///////////////////
    // Internal Functions
    ///////////////////
    function _redeemCollateral(address tokenCollateral, uint256 amount, address from, address to) private {
        s_collateralDeposited[from][tokenCollateral] -= amount;

        emit CollateralRedeemed(from, to, tokenCollateral, amount);

        bool success = IERC20(tokenCollateral).transfer(to, amount);
        if (!success) revert DSCEngine__TokenTransferFailed();

        // Check that health factor is not broken
        _revertIfHealthFactorIsBroken(from);
    }

    function _burnDsc(uint256 amount, address onBehalfOf, address dscFrom) private {
        s_dscMinted[onBehalfOf] -= amount;

        bool success = i_dsc.transferFrom(dscFrom, address(this), amount);
        if (!success) revert DSCEngine__TokenTransferFailed();

        i_dsc.burn(amount);
    }

    function _mintDsc(uint256 amount) private {
        s_dscMinted[msg.sender] += amount;
        // if they minted too much
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amount);

        if (minted != true) {
            revert DSCEngine__MintFailed();
        }
    }

    function _depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) private {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;

        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) revert DSCEngine__TokenTransferFailed();
    }

    function _revertIfHealthFactorIsBroken(address user) private view {
        uint256 healthFactor = _healthFactor(user);

        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(healthFactor);
        }
    }

    /**
     * @param user The address to query
     */
    function _healthFactor(address user) private view returns (uint256) {
        // total dsc minted
        // total collateral value
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return ((collateralAdjustedForThreshold * PRECISION) / totalDscMinted);
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_dscMinted[user];
        collateralValueInUsd = getAccountCollateralValueInUsd(user);
    }

    ///////////////////
    // Public and External View Functions
    ///////////////////
    function getAccountCollateralValueInUsd(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // loop through each coll token, get amount deposited, map it to price
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];

            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface feed = AggregatorV3Interface(s_priceFeeds[token]);

        (, int256 price,,,) = feed.latestRoundData();

        // Chainlink returns 1e8
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // $100e18 USD Debt
        // 1 ETH = 2000 USD
        // The returned value from Chainlink will be 2000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }
}
