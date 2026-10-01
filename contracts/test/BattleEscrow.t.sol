// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {BattleEscrow} from "../src/BattleEscrow.sol";

contract BattleEscrowTest is Test {
    BattleEscrow escrow;
    address admin = makeAddr("admin");
    address resolver = makeAddr("resolver");
    address treasury = makeAddr("treasury");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        escrow = new BattleEscrow(admin, resolver, treasury);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    function test_CreateEscrow_RecordsChallenger() public {
        vm.prank(alice);
        escrow.createEscrow{value: 1 ether}(1);

        (address challenger, address acceptor, uint256 wagerWei, BattleEscrow.Status status) = escrow.escrows(1);
        assertEq(challenger, alice);
        assertEq(acceptor, address(0));
        assertEq(wagerWei, 1 ether);
        assertEq(uint8(status), uint8(BattleEscrow.Status.Open));
        assertEq(address(escrow).balance, 1 ether);
    }

    function test_CreateEscrow_RevertsWithZeroValue() public {
        vm.prank(alice);
        vm.expectRevert(BattleEscrow.NoWager.selector);
        escrow.createEscrow{value: 0}(1);
    }

    function test_CreateEscrow_RevertsIfChallengeIdAlreadyUsed() public {
        vm.prank(alice);
        escrow.createEscrow{value: 1 ether}(1);

        vm.prank(bob);
        vm.expectRevert(BattleEscrow.EscrowAlreadyExists.selector);
        escrow.createEscrow{value: 1 ether}(1);
    }

    function test_AcceptEscrow_RequiresMatchingWager() public {
        vm.prank(alice);
        escrow.createEscrow{value: 1 ether}(1);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(BattleEscrow.WrongWagerAmount.selector, 1 ether, 0.5 ether));
        escrow.acceptEscrow{value: 0.5 ether}(1);
    }

    function test_AcceptEscrow_MovesToAccepted() public {
        vm.prank(alice);
        escrow.createEscrow{value: 1 ether}(1);
        vm.prank(bob);
        escrow.acceptEscrow{value: 1 ether}(1);

        (, address acceptor,, BattleEscrow.Status status) = escrow.escrows(1);
        assertEq(acceptor, bob);
        assertEq(uint8(status), uint8(BattleEscrow.Status.Accepted));
        assertEq(address(escrow).balance, 2 ether);
    }

    function test_Resolve_PaysWinnerMinusRakeAndFeeToTreasury() public {
        vm.prank(alice);
        escrow.createEscrow{value: 1 ether}(1);
        vm.prank(bob);
        escrow.acceptEscrow{value: 1 ether}(1);

        uint256 aliceBefore = alice.balance;
        uint256 treasuryBefore = treasury.balance;

        vm.prank(resolver);
        escrow.resolve(1, alice);

        // Pot is 2 ether, default rake is 500 bps (5%): 0.1 ether fee, 1.9 ether payout.
        assertEq(alice.balance, aliceBefore + 1.9 ether);
        assertEq(treasury.balance, treasuryBefore + 0.1 ether);
        assertEq(address(escrow).balance, 0);

        (,,, BattleEscrow.Status status) = escrow.escrows(1);
        assertEq(uint8(status), uint8(BattleEscrow.Status.Resolved));
    }

    function test_Resolve_RevertsForNonResolver() public {
        vm.prank(alice);
        escrow.createEscrow{value: 1 ether}(1);
        vm.prank(bob);
        escrow.acceptEscrow{value: 1 ether}(1);

        vm.prank(alice);
        vm.expectRevert();
        escrow.resolve(1, alice);
    }

    function test_Resolve_RevertsForUnknownWinner() public {
        vm.prank(alice);
        escrow.createEscrow{value: 1 ether}(1);
        vm.prank(bob);
        escrow.acceptEscrow{value: 1 ether}(1);

        address mallory = makeAddr("mallory");
        vm.prank(resolver);
        vm.expectRevert(BattleEscrow.InvalidWinner.selector);
        escrow.resolve(1, mallory);
    }

    function test_Resolve_RevertsIfNotYetAccepted() public {
        vm.prank(alice);
        escrow.createEscrow{value: 1 ether}(1);

        vm.prank(resolver);
        vm.expectRevert(BattleEscrow.EscrowNotAccepted.selector);
        escrow.resolve(1, alice);
    }

    function test_CancelEscrow_RefundsChallengerBeforeAccept() public {
        vm.prank(alice);
        escrow.createEscrow{value: 1 ether}(1);

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        escrow.cancelEscrow(1);

        assertEq(alice.balance, aliceBefore + 1 ether);
        (,,, BattleEscrow.Status status) = escrow.escrows(1);
        assertEq(uint8(status), uint8(BattleEscrow.Status.Cancelled));
    }

    function test_CancelEscrow_ResolverCanAlsoCancelForExpiry() public {
        vm.prank(alice);
        escrow.createEscrow{value: 1 ether}(1);

        vm.prank(resolver);
        escrow.cancelEscrow(1);

        (,,, BattleEscrow.Status status) = escrow.escrows(1);
        assertEq(uint8(status), uint8(BattleEscrow.Status.Cancelled));
    }

    function test_CancelEscrow_RevertsForStranger() public {
        vm.prank(alice);
        escrow.createEscrow{value: 1 ether}(1);

        vm.prank(bob);
        vm.expectRevert(BattleEscrow.NotChallenger.selector);
        escrow.cancelEscrow(1);
    }

    function test_CancelEscrow_RevertsOnceAccepted() public {
        vm.prank(alice);
        escrow.createEscrow{value: 1 ether}(1);
        vm.prank(bob);
        escrow.acceptEscrow{value: 1 ether}(1);

        vm.prank(alice);
        vm.expectRevert(BattleEscrow.EscrowNotOpen.selector);
        escrow.cancelEscrow(1);
    }

    function test_SetRakeBps_RevertsAboveMax() public {
        vm.prank(admin);
        vm.expectRevert(BattleEscrow.RakeTooHigh.selector);
        escrow.setRakeBps(2001);
    }

    function test_SetRakeBps_RevertsForNonAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        escrow.setRakeBps(1000);
    }
}
