// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Deployers} from "./helpers/Deployers.sol";
import {EggNFT} from "../src/EggNFT.sol";

contract EggNFTTest is Deployers {
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        _deployAll();
    }

    function test_BackendCanLayEggDirectly() public {
        vm.prank(backendSigner);
        uint256 eggId = eggNFT.layEgg(alice, 2, 3, uint64(block.timestamp + 1 days), 0, 0, false);
        assertEq(eggNFT.ownerOf(eggId), alice);

        EggNFT.Egg memory egg = eggNFT.getEggInfo(eggId);
        assertEq(egg.rarity, 2);
        assertEq(egg.species, 3);
        assertFalse(egg.isRotten);
    }

    function test_UnauthorizedCallerCannotLayEgg() public {
        vm.prank(alice);
        vm.expectRevert();
        eggNFT.layEgg(alice, 1, 0, uint64(block.timestamp), 0, 0, false);
    }

    function test_SpeedUpHatch_SkipsRemainingTimeAndPaysTreasury() public {
        vm.prank(backendSigner);
        uint256 eggId = eggNFT.layEgg(alice, 1, 0, uint64(block.timestamp + 10 hours), 0, 0, false);

        vm.deal(alice, 1 ether);
        uint256 treasuryBefore = treasury.balance;
        vm.prank(alice);
        eggNFT.speedUpHatch{value: 0.01 ether}(eggId); // 10h * 0.001 ether/h

        assertTrue(eggNFT.isHatchable(eggId));
        assertEq(treasury.balance, treasuryBefore + 0.01 ether);
    }

    function test_SpeedUpHatch_RefundsExcessPayment() public {
        vm.prank(backendSigner);
        uint256 eggId = eggNFT.layEgg(alice, 1, 0, uint64(block.timestamp + 2 hours), 0, 0, false);

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        eggNFT.speedUpHatch{value: 0.1 ether}(eggId); // only 0.002 ether needed for 2h
        assertEq(alice.balance, 1 ether - 0.002 ether);
    }

    function test_SpeedUpHatch_RevertsOnUnderpayment() public {
        vm.prank(backendSigner);
        uint256 eggId = eggNFT.layEgg(alice, 1, 0, uint64(block.timestamp + 10 hours), 0, 0, false);

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(EggNFT.InsufficientPayment.selector, 0.01 ether, 0.001 ether));
        eggNFT.speedUpHatch{value: 0.001 ether}(eggId);
    }

    function test_SpeedUpHatch_RevertsIfAlreadyHatchable() public {
        vm.prank(backendSigner);
        uint256 eggId = eggNFT.layEgg(alice, 1, 0, uint64(block.timestamp), 0, 0, false);

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(EggNFT.EggAlreadyHatchable.selector, eggId));
        eggNFT.speedUpHatch{value: 0.01 ether}(eggId);
    }

    function test_SpeedUpHatch_RevertsForNonOwner() public {
        vm.prank(backendSigner);
        uint256 eggId = eggNFT.layEgg(alice, 1, 0, uint64(block.timestamp + 10 hours), 0, 0, false);

        vm.deal(bob, 1 ether);
        vm.prank(bob);
        vm.expectRevert(EggNFT.NotEggOwner.selector);
        eggNFT.speedUpHatch{value: 0.01 ether}(eggId);
    }

    function test_HatchEgg_FullLifecycle_MintsLiveCreature() public {
        uint256 creatureId = _purchaseCommonCreature(alice);
        vm.prank(alice);
        uint256 eggId = creatureNFT.layEgg(creatureId);

        EggNFT.Egg memory egg = eggNFT.getEggInfo(eggId);
        assertFalse(eggNFT.isHatchable(eggId));

        // Tend the egg right before its timer is up so care is fresh (100) when it becomes
        // hatchable -- a rarity-1 egg's 24h incubation fully decays a 100 starting care level
        // (5%/hr * 24h = 120%), so hatching this egg without any tending is expected to fail.
        vm.warp(egg.hatchTime - 1 hours);
        _giveFeed(alice, 100 ether);
        vm.prank(alice);
        eggNFT.tendEgg(eggId);

        vm.warp(egg.hatchTime);
        assertTrue(eggNFT.isHatchable(eggId));

        vm.prank(alice);
        uint256 newCreatureId = eggNFT.hatchEgg(eggId);

        assertEq(creatureNFT.ownerOf(newCreatureId), alice);
        assertTrue(creatureNFT.isAlive(newCreatureId));

        // Egg NFT should no longer exist.
        vm.expectRevert();
        eggNFT.ownerOf(eggId);
    }

    function test_HatchEgg_RevertsBeforeReady() public {
        uint256 creatureId = _purchaseCommonCreature(alice);
        vm.prank(alice);
        uint256 eggId = creatureNFT.layEgg(creatureId);

        vm.prank(alice);
        vm.expectRevert();
        eggNFT.hatchEgg(eggId);
    }

    function test_HatchEgg_RevertsForNonOwner() public {
        vm.prank(backendSigner);
        uint256 eggId = eggNFT.layEgg(alice, 1, 0, uint64(block.timestamp), 0, 0, false);

        vm.prank(bob);
        vm.expectRevert(EggNFT.NotEggOwner.selector);
        eggNFT.hatchEgg(eggId);
    }

    function test_RottenEgg_CannotHatch_ButCanBeDiscarded() public {
        vm.prank(backendSigner);
        uint256 eggId = eggNFT.layEgg(alice, 1, 0, uint64(block.timestamp), 0, 0, true);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(EggNFT.EggIsRotten.selector, eggId));
        eggNFT.hatchEgg(eggId);

        vm.prank(alice);
        eggNFT.discardRottenEgg(eggId);

        vm.expectRevert();
        eggNFT.ownerOf(eggId);
    }

    function test_DiscardRottenEgg_RevertsIfNotRotten() public {
        vm.prank(backendSigner);
        uint256 eggId = eggNFT.layEgg(alice, 1, 0, uint64(block.timestamp), 0, 0, false);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(EggNFT.EggNotRotten.selector, eggId));
        eggNFT.discardRottenEgg(eggId);
    }

    function test_DiscardRottenEgg_RevertsForNonOwner() public {
        vm.prank(backendSigner);
        uint256 eggId = eggNFT.layEgg(alice, 1, 0, uint64(block.timestamp), 0, 0, true);

        vm.prank(bob);
        vm.expectRevert(EggNFT.NotEggOwner.selector);
        eggNFT.discardRottenEgg(eggId);
    }

    function test_IsHatchable_FalseBeforeReadyTrueAfter() public {
        vm.prank(backendSigner);
        uint256 eggId = eggNFT.layEgg(alice, 1, 0, uint64(block.timestamp + 1 days), 0, 0, false);

        assertFalse(eggNFT.isHatchable(eggId));

        // Tend shortly before the timer is up so care is still high when it fires.
        vm.warp(block.timestamp + 23 hours);
        _giveFeed(alice, 100 ether);
        vm.prank(alice);
        eggNFT.tendEgg(eggId);

        vm.warp(block.timestamp + 1 hours);
        assertTrue(eggNFT.isHatchable(eggId));
    }

    function test_IsHatchable_FalseWhenCareTooLowEvenAfterTimer() public {
        vm.prank(backendSigner);
        uint256 eggId = eggNFT.layEgg(alice, 1, 0, uint64(block.timestamp + 1 days), 0, 0, false);

        // Never tended: care decays to 0 well before the 24h timer is up (5%/hr for rarity 1).
        vm.warp(block.timestamp + 1 days);
        assertFalse(eggNFT.isHatchable(eggId));

        // Read before pranking: calling this inline inside expectRevert's argument list would
        // itself consume the single-use vm.prank before hatchEgg ever runs.
        uint8 minCare = eggNFT.MIN_CARE_TO_HATCH();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(EggNFT.EggCareTooLow.selector, eggId, 0, minCare));
        eggNFT.hatchEgg(eggId);
    }

    function test_BreedingLab_ProducesEggWithBothParents() public {
        uint256 p1 = _purchaseCommonCreature(alice);
        uint256 p2 = _purchaseCommonCreature(alice);
        _giveFeed(alice, 1000 ether);
        vm.deal(alice, 1 ether);

        vm.prank(alice);
        uint256 eggId = creatureNFT.breedCreatures{value: 0.01 ether}(p1, p2);

        EggNFT.Egg memory egg = eggNFT.getEggInfo(eggId);
        assertEq(egg.parent1, p1);
        assertEq(egg.parent2, p2);
        assertGe(egg.rarity, 1);
        assertLe(egg.rarity, 5);
    }

    // ---------------------------------------------------------------------
    // Incubation care
    // ---------------------------------------------------------------------

    function test_CareLevel_StartsFullAndDecaysByRarity() public {
        vm.prank(backendSigner);
        uint256 commonEgg = eggNFT.layEgg(alice, 1, 0, uint64(block.timestamp + 1 days), 0, 0, false);
        vm.prank(backendSigner);
        uint256 legendaryEgg = eggNFT.layEgg(alice, 5, 12, uint64(block.timestamp + 3 days), 0, 0, false);

        assertEq(eggNFT.getCareLevel(commonEgg), 100);
        assertEq(eggNFT.getCareLevel(legendaryEgg), 100);

        vm.warp(block.timestamp + 5 hours);
        // Common: 5%/hr * 5h = 25% decay. Legendary: 13%/hr * 5h = 65% decay.
        assertEq(eggNFT.getCareLevel(commonEgg), 75);
        assertEq(eggNFT.getCareLevel(legendaryEgg), 35);
    }

    function test_TendEgg_ResetsCareAndBurnsFeedScaledByRarity() public {
        vm.prank(backendSigner);
        uint256 eggId = eggNFT.layEgg(alice, 3, 6, uint64(block.timestamp + 2 days), 0, 0, false);
        _giveFeed(alice, 100 ether);

        vm.warp(block.timestamp + 4 hours);
        assertLt(eggNFT.getCareLevel(eggId), 100);

        vm.prank(alice);
        eggNFT.tendEgg(eggId);

        assertEq(eggNFT.getCareLevel(eggId), 100);
        assertEq(feedToken.balanceOf(alice), 100 ether - eggNFT.TEND_COST_PER_RARITY() * 3);
    }

    function test_TendEgg_RevertsForNonOwner() public {
        vm.prank(backendSigner);
        uint256 eggId = eggNFT.layEgg(alice, 1, 0, uint64(block.timestamp + 1 days), 0, 0, false);

        vm.prank(bob);
        vm.expectRevert(EggNFT.NotEggOwner.selector);
        eggNFT.tendEgg(eggId);
    }

    function test_CheckEggCare_SpoilsAfterTwelveHoursAtZeroCare() public {
        vm.prank(backendSigner);
        uint256 eggId = eggNFT.layEgg(alice, 1, 0, uint64(block.timestamp + 10 days), 0, 0, false);

        // Care hits 0 at +20h (5%/hr for rarity 1).
        vm.warp(block.timestamp + 20 hours);
        eggNFT.checkEggCare(eggId);
        assertFalse(eggNFT.getEggInfo(eggId).isRotten);

        // Not yet spoiled just before the 12h grace period elapses.
        vm.warp(block.timestamp + 11 hours);
        eggNFT.checkEggCare(eggId);
        assertFalse(eggNFT.getEggInfo(eggId).isRotten);

        // Spoiled once the grace period elapses.
        vm.warp(block.timestamp + 1 hours + 1);
        eggNFT.checkEggCare(eggId);
        assertTrue(eggNFT.getEggInfo(eggId).isRotten);
    }

    function test_CheckEggCare_TendingResetsNeglectClock() public {
        vm.prank(backendSigner);
        uint256 eggId = eggNFT.layEgg(alice, 1, 0, uint64(block.timestamp + 10 days), 0, 0, false);
        _giveFeed(alice, 100 ether);

        vm.warp(block.timestamp + 20 hours);
        eggNFT.checkEggCare(eggId);

        vm.warp(block.timestamp + 10 hours);
        vm.prank(alice);
        eggNFT.tendEgg(eggId);

        vm.warp(block.timestamp + 11 hours);
        eggNFT.checkEggCare(eggId);
        assertFalse(eggNFT.getEggInfo(eggId).isRotten);
    }

    function test_HatchEgg_PerfectCareGrantsHappinessBonus() public {
        uint256 creatureId = _purchaseCommonCreature(alice);
        vm.prank(alice);
        uint256 eggId = creatureNFT.layEgg(creatureId);
        _giveFeed(alice, 100 ether);

        EggNFT.Egg memory egg = eggNFT.getEggInfo(eggId);
        vm.warp(egg.hatchTime); // untended, but care never touched 0 within the first cycle window
        // Tend right at the hatch boundary so care reads exactly 100 for the "perfect care" tier.
        vm.prank(alice);
        eggNFT.tendEgg(eggId);

        vm.prank(alice);
        uint256 newCreatureId = eggNFT.hatchEgg(eggId);

        assertEq(creatureNFT.getCreature(newCreatureId).happiness, 80);
    }
}
