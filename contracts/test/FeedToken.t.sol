// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {FeedToken} from "../src/FeedToken.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract FeedTokenTest is Test {
    FeedToken token;
    address admin = makeAddr("admin");
    address player = makeAddr("player");
    address randomCaller = makeAddr("randomCaller");

    function setUp() public {
        vm.prank(admin);
        token = new FeedToken(admin);
    }

    function test_MinterCanMintReward() public {
        vm.prank(admin);
        token.mintReward(player, 20 ether);
        assertEq(token.balanceOf(player), 20 ether);
    }

    function test_NonMinterCannotMintReward() public {
        vm.prank(randomCaller);
        vm.expectRevert();
        token.mintReward(player, 20 ether);
    }

    function test_BurnerCanBurnFeed() public {
        bytes32 burnerRole = token.BURNER_ROLE();

        vm.prank(admin);
        token.mintReward(player, 20 ether);

        vm.prank(admin);
        token.grantRole(burnerRole, randomCaller);

        vm.prank(randomCaller);
        token.burnFeed(player, 5 ether);

        assertEq(token.balanceOf(player), 15 ether);
    }

    function test_NonBurnerCannotBurnFeed() public {
        vm.prank(admin);
        token.mintReward(player, 20 ether);

        vm.prank(randomCaller);
        vm.expectRevert();
        token.burnFeed(player, 5 ether);
    }

    function test_BurnRevertsOnInsufficientBalance() public {
        bytes32 burnerRole = token.BURNER_ROLE();

        vm.prank(admin);
        token.grantRole(burnerRole, admin);

        vm.prank(admin);
        vm.expectRevert();
        token.burnFeed(player, 5 ether);
    }
}
