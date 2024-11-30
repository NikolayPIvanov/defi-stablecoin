// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IDSCEngine {
    /**
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of tokenCollateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) external;
    function redeemCollateral() external;
    function depositCollateralAndMintDsc() external;
    function redeemCollateralForDsc() external;
    function liquidate() external;
    function getHealthFactory() external view;
    function burnDsc() external;

    /**
     * @notice Check if the collateral value > DSC amount
     * @param amount Amount of DSC to mint
     */
    function mintDsc(uint256 amount) external;
}
