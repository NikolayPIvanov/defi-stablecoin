// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IDSCEngine} from "./IDSCEngine.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

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

    ///////////////////
    // State Variables
    ///////////////////
    DecentralizedStableCoin private i_dsc;

    /// @dev Mapping of token address to price feed address
    mapping(address collateralToken => address priceFeed) private s_priceFeeds;
    /// @dev Amount of collateral deposited by user
    mapping(address user => mapping(address collateralToken => uint256 amount)) private s_collateralDeposited;

    ///////////////////
    // Events
    ///////////////////
    event CollateralDeposited(address indexed user, address indexed collateralToken, uint256 amount);

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
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ///////////////////
    // External Functions
    ///////////////////
    /**
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

    function depositCollateralAndMintDsc() external override {}

    function redeemCollateralForDsc() external override {}

    function redeemCollateral() external override {}

    function liquidate() external override {}

    function getHealthFactory() external view override {}

    function burnDsc() external override {}

    function mintDsc() external override {}

    ///////////////////
    // Internal Functions
    ///////////////////
    function _depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral) private {
        s_collateralDeposited[msg.sender][_tokenCollateralAddress] += _amountCollateral;

        emit CollateralDeposited(msg.sender, _tokenCollateralAddress, _amountCollateral);
    }
}
