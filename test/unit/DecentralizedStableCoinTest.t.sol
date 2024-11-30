// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

contract DecentralizedStableCoinTest is Test {
    DeployDSC public deployer;
    DecentralizedStableCoin public dsc;

    string private constant NAME = "Decentralized Stable Coin";
    string private constant SYMBOL = "DSC";
    uint256 private constant AMOUNT = 1e18;

    uint256 public DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address public user = makeAddr("user");
    address public receiver = makeAddr("receiver");

    constructor() {
        deployer = new DeployDSC();
    }

    function setUp() public {
        (dsc,,) = deployer.run();
    }

    function testConstructorNameIsDefined() public view {
        assert(keccak256(abi.encodePacked(dsc.name())) == keccak256(abi.encodePacked(NAME)));
    }

    function testConstructorSymbolIsDefined() public view {
        assert(keccak256(abi.encodePacked(dsc.symbol())) == keccak256(abi.encodePacked(SYMBOL)));
    }

    function testMintOnlyOwnerCanCall() public {
        vm.prank(user);
        vm.expectRevert();

        dsc.mint(receiver, 1e18);
    }

    function testMintMustNotMintToZeroAddress() public {
        vm.prank(dsc.owner());
        vm.expectRevert();

        dsc.mint(address(0), 1e18);
    }

    function testMintMustMintMoreThanZero() public {
        vm.prank(dsc.owner());
        vm.expectRevert();

        dsc.mint(receiver, 0);
    }

    function testMintMustMintAmountToReceiver() public {
        vm.prank(dsc.owner());
        bool result = dsc.mint(receiver, AMOUNT);
        uint256 balance = dsc.balanceOf(receiver);

        assert(result);
        assertEq(balance, AMOUNT);
    }

    function testBurnOnlyOwnerCanCall() public {
        vm.prank(user);
        vm.expectRevert();

        dsc.burn(1e18);
    }

    function testBurnCannotBurnLessThanOrEqualToZero() public {
        vm.prank(dsc.owner());
        vm.expectRevert();
        dsc.burn(0);
    }

    function testBurnCannotBurnMoreThanBalance() public {
        vm.prank(dsc.owner());
        dsc.mint(receiver, AMOUNT);

        vm.prank(dsc.owner());
        vm.expectRevert();
        dsc.burn(101);
    }

    function testBurnRemoveBurntTokensFromBalance() public {
        vm.prank(dsc.owner());
        dsc.mint(receiver, AMOUNT);

        vm.prank(dsc.owner());
        vm.expectRevert();
        dsc.burn(101);
    }

    function testBurnMustBurnAmountFromBalance() public {
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
