// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";

contract DecentralizedStableCoinTest is Test {
    DeployDSC public deployer;
    DecentralizedStableCoin public dsc;

    string constant NAME = "Decentralized Stable Coin";
    string constant SYMBOL = "DSC";
    uint256 constant AMOUNT = 1e18;

    uint256 public DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address public user = makeAddr("user");
    address public receiver = makeAddr("receiver");

    constructor() {
        deployer = new DeployDSC();
    }

    function setUp() public {
        dsc = deployer.run();
    }

    function test_constructor_nameIsDefined() public view {
        assert(keccak256(abi.encodePacked(dsc.name())) == keccak256(abi.encodePacked(NAME)));
    }

    function test_constructor_symbolIsDefined() public view {
        assert(keccak256(abi.encodePacked(dsc.symbol())) == keccak256(abi.encodePacked(SYMBOL)));
    }

    function test_mint_onlyOwnerCanCall() public {
        vm.prank(user);
        vm.expectRevert();

        dsc.mint(receiver, 1e18);
    }

    function test_mint_mustNotMintToZeroAddress() public {
        vm.prank(dsc.owner());
        vm.expectRevert();

        dsc.mint(address(0), 1e18);
    }

    function test_mint_mustMintMoreThanZero() public {
        vm.prank(dsc.owner());
        vm.expectRevert();

        dsc.mint(receiver, 0);
    }

    function test_mint_mustMintAmountToReceiver() public {
        vm.prank(dsc.owner());
        bool result = dsc.mint(receiver, AMOUNT);
        uint256 balance = dsc.balanceOf(receiver);

        assert(result);
        assertEq(balance, AMOUNT);
    }

    function test_burn_onlyOwnerCanCall() public {
        vm.prank(user);
        vm.expectRevert();

        dsc.burn(1e18);
    }

    function test_burn_cannotBurnLessThanOrEqualToZero() public {
        vm.prank(dsc.owner());
        vm.expectRevert();
        dsc.burn(0);
    }

    function test_burn_cannotBurnMoreThanBalance() public {
        vm.prank(dsc.owner());
        dsc.mint(receiver, AMOUNT);

        vm.prank(dsc.owner());
        vm.expectRevert();
        dsc.burn(101);
    }

    function test_burn_removeBurntTokensFromBalance() public {
        vm.prank(dsc.owner());
        dsc.mint(receiver, AMOUNT);

        vm.prank(dsc.owner());
        vm.expectRevert();
        dsc.burn(101);
    }

    function test_burn_mustBurnAmountFromBalance() public {
        // Mint some tokens to our receiver so it can burn
        address owner = dsc.owner();
        vm.startPrank(owner);
        dsc.mint(owner, AMOUNT * 2);
        dsc.burn(AMOUNT);
        vm.stopPrank();

        uint256 leftOverBalance = dsc.balanceOf(owner);

        assert(leftOverBalance == AMOUNT);
    }
}
