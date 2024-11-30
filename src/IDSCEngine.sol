// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IDSCEngine {
    function depositCollateralAndMintDsc() external;
    function redeemCollateralForDsc() external;
    function redeemCollateral() external;
    function liquidate() external;
    function getHealthFactory() external view;
    function burnDsc() external;
    function mintDsc() external;
}
