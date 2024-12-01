// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IDSCEngine {
    /**
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of tokenCollateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) external;
    function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDsc)
        external;
    function redeemCollateral(address tokenCollateral, uint256 amount) external;
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external;
    function liquidate(address tokenCollateral, address user, uint256 debt) external;
    function getHealthFactory() external view;
    function burnDsc(uint256 amount) external;

    /**
     * @notice Check if the collateral value > DSC amount
     * @param amount Amount of DSC to mint
     */
    function mintDsc(uint256 amount) external;
}
