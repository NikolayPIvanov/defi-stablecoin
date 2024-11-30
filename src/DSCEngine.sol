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

    ///////////////////
    // State Variables
    ///////////////////
    DecentralizedStableCoin private i_dsc;

    uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means you need to be 200% over-collateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

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
    event CollateralRedeemed(address indexed user, address indexed collateralToken, uint256 amount);

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
        _redeemCollateral(tokenCollateral, amount);
    }

    function burnDsc(uint256 amount) external override nonZeroAmount(amount) {
        _burnDsc(amount);
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
        _burnDsc(amountDscToBurn);
        _redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function liquidate() external override {}

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
    function _redeemCollateral(address tokenCollateral, uint256 amount) private {
        s_collateralDeposited[msg.sender][tokenCollateral] -= amount;

        emit CollateralRedeemed(msg.sender, tokenCollateral, amount);

        bool success = IERC20(tokenCollateral).transfer(msg.sender, amount);
        if (!success) revert DSCEngine__TokenTransferFailed();

        // Check that health factor is not broken
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function _burnDsc(uint256 amount) private {
        s_dscMinted[msg.sender] -= amount;

        bool success = i_dsc.transferFrom(msg.sender, address(this), amount);
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
        return ((uint256(price) * 1e10) * amount) / 1e18;
    }
}
