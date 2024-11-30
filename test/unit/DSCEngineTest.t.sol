// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC public deployer;
    DecentralizedStableCoin public dsc;
    DSCEngine public engine;
    HelperConfig public config;
    address public ethUsdPriceFeed;
    address public weth;

    address public user = address(1);

    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_DSC_BALANCE = 5 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();

        (ethUsdPriceFeed,, weth,,) = config.activeNetworkConfig();

        ERC20Mock(weth).approve(user, STARTING_DSC_BALANCE);
    }

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        // 15 ETH * 2000 = 30,000e18 USD
        uint256 expectedUsdValue = 30000e18;

        uint256 usdValue = engine.getUsdValue(weth, ethAmount);

        assertEq(usdValue, expectedUsdValue);
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZeroAmount.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }
}
