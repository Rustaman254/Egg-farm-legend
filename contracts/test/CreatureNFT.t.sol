// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Deployers} from "./helpers/Deployers.sol";
import {CreatureNFT} from "../src/CreatureNFT.sol";
import {EggNFT} from "../src/EggNFT.sol";

contract CreatureNFTTest is Deployers {
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        _deployAll();
    }

    function test_PurchaseCreature_MintsWithExpectedDefaults() public {
        uint256 tokenId = _purchaseCommonCreature(alice);

        assertEq(creatureNFT.ownerOf(tokenId), alice);
        CreatureNFT.Creature memory c = creatureNFT.getCreature(tokenId);
        assertEq(c.rarity, 1);
        assertEq(c.happiness, 50);
        assertEq(c.breedCount, 0);
        assertFalse(c.isDead);
        assertEq(creatureNFT.getHunger(tokenId), 100);
    }

    function test_PurchaseCreature_RevertsOnUnderpayment() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert();
        creatureNFT.purchaseCreature{value: 0.01 ether}(1);
    }

    function test_PurchaseCreature_RevertsOnInvalidTier() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert();
        creatureNFT.purchaseCreature{value: 1 ether}(9);
    }

    function test_ImmatureCreature_CannotBeTransferred() public {
        uint256 tokenId = _purchaseCommonCreature(alice);
        assertFalse(creatureNFT.isMature(tokenId));
        uint64 maturesAt = creatureNFT.getCreature(tokenId).maturesAt;

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CreatureNFT.CreatureNotMature.selector, tokenId, maturesAt));
        creatureNFT.transferFrom(alice, bob, tokenId);
    }

    function test_MatureCreature_CanBeTransferred() public {
        uint256 tokenId = _purchaseCommonCreature(alice);
        vm.warp(block.timestamp + creatureNFT.maturationDuration(1) + 1);
        assertTrue(creatureNFT.isMature(tokenId));

        vm.prank(alice);
        creatureNFT.transferFrom(alice, bob, tokenId);
        assertEq(creatureNFT.ownerOf(tokenId), bob);
    }

    function test_ImmatureCreature_CanStillBeFed() public {
        // Rarity 1 matures in exactly 1h, the same granularity hunger decays at, so there's no
        // window where it's both hungry and still immature -- use rarity 2 (2h) for headroom.
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        uint256 tokenId = creatureNFT.purchaseCreature{value: 0.08 ether}(2);
        _giveFeed(alice, 100 ether);
        vm.warp(block.timestamp + 90 minutes);

        assertFalse(creatureNFT.isMature(tokenId));
        assertEq(creatureNFT.getHunger(tokenId), 90);
        vm.prank(alice);
        creatureNFT.feedCreature(tokenId);
        assertEq(creatureNFT.getHunger(tokenId), 100);
    }

    function test_HungerDecaysTenPercentPerHour() public {
        uint256 tokenId = _purchaseCommonCreature(alice);
        vm.warp(block.timestamp + 3 hours);
        assertEq(creatureNFT.getHunger(tokenId), 70);
    }

    function test_HungerFloorsAtZero() public {
        uint256 tokenId = _purchaseCommonCreature(alice);
        vm.warp(block.timestamp + 100 hours);
        assertEq(creatureNFT.getHunger(tokenId), 0);
    }

    function test_FeedCreature_RestoresHungerAndRaisesHappiness() public {
        uint256 tokenId = _purchaseCommonCreature(alice);
        _giveFeed(alice, 100 ether);

        vm.warp(block.timestamp + 5 hours);
        assertEq(creatureNFT.getHunger(tokenId), 50);

        vm.prank(alice);
        creatureNFT.feedCreature(tokenId);

        assertEq(creatureNFT.getHunger(tokenId), 100);
        CreatureNFT.Creature memory c = creatureNFT.getCreature(tokenId);
        assertEq(c.happiness, 60);
        // 50% hunger deficit -> half the full 5 FEED meal price.
        assertEq(feedToken.balanceOf(alice), 97.5 ether);
    }

    function test_FeedCreature_CostScalesWithHungerDeficit() public {
        uint256 tokenId = _purchaseCommonCreature(alice);
        _giveFeed(alice, 100 ether);

        // Barely hungry (1h -> 10% deficit) costs a tenth of the full meal price.
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        creatureNFT.feedCreature(tokenId);
        assertEq(feedToken.balanceOf(alice), 99.5 ether);

        // Fully starved (10h+ -> 100% deficit) costs the full meal price.
        vm.warp(block.timestamp + 10 hours);
        vm.prank(alice);
        creatureNFT.feedCreature(tokenId);
        assertEq(feedToken.balanceOf(alice), 94.5 ether);
    }

    function test_FeedCreature_RevertsWhenAlreadyFull() public {
        uint256 tokenId = _purchaseCommonCreature(alice);
        _giveFeed(alice, 100 ether);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CreatureNFT.CreatureNotHungry.selector, tokenId));
        creatureNFT.feedCreature(tokenId);
    }

    function test_FeedCreature_RevertsForNonOwner() public {
        uint256 tokenId = _purchaseCommonCreature(alice);
        _giveFeed(bob, 100 ether);

        vm.prank(bob);
        vm.expectRevert(CreatureNFT.NotCreatureOwner.selector);
        creatureNFT.feedCreature(tokenId);
    }

    function test_CheckStarvation_KillsAfterTwentyFourHoursAtZeroHunger() public {
        uint256 tokenId = _purchaseCommonCreature(alice);

        // Hunger hits 0 at +10h. Mark starvation start.
        vm.warp(block.timestamp + 10 hours);
        creatureNFT.checkStarvation(tokenId);
        assertTrue(creatureNFT.isAlive(tokenId));

        // Not dead yet at +10h+23h since zero.
        vm.warp(block.timestamp + 23 hours);
        creatureNFT.checkStarvation(tokenId);
        assertTrue(creatureNFT.isAlive(tokenId));

        // Dead at +10h+24h since zero.
        vm.warp(block.timestamp + 1 hours + 1);
        creatureNFT.checkStarvation(tokenId);
        assertFalse(creatureNFT.isAlive(tokenId));
    }

    function test_CheckStarvation_FeedingResetsClock() public {
        uint256 tokenId = _purchaseCommonCreature(alice);
        _giveFeed(alice, 100 ether);

        vm.warp(block.timestamp + 10 hours);
        creatureNFT.checkStarvation(tokenId);

        vm.warp(block.timestamp + 20 hours);
        vm.prank(alice);
        creatureNFT.feedCreature(tokenId);

        vm.warp(block.timestamp + 23 hours);
        creatureNFT.checkStarvation(tokenId);
        assertTrue(creatureNFT.isAlive(tokenId));
    }

    function test_LayEgg_MintsEggAndRespectsCooldown() public {
        uint256 tokenId = _purchaseCommonCreature(alice);

        vm.prank(alice);
        uint256 eggId = creatureNFT.layEgg(tokenId);
        assertEq(eggNFT.ownerOf(eggId), alice);

        vm.prank(alice);
        vm.expectRevert();
        creatureNFT.layEgg(tokenId);

        vm.warp(block.timestamp + 2 hours + 1);
        vm.prank(alice);
        creatureNFT.layEgg(tokenId); // should succeed now
    }

    function test_LayEgg_RevertsWhenUnhappy() public {
        uint256 tokenId = _purchaseCommonCreature(alice);
        _giveFeed(alice, 100 ether);

        // One neglect episode: 50 - 25 = 25, and hunger is 0 -- reverts as starving first, not
        // yet a happiness test (see test_LayEgg_RevertsWhenStarving for that gate in isolation).
        vm.warp(block.timestamp + 10 hours);
        creatureNFT.checkStarvation(tokenId);
        CreatureNFT.Creature memory c = creatureNFT.getCreature(tokenId);
        assertEq(c.happiness, 25);

        // Feed once: hunger is fixed (100, no longer "starving"), but happiness (25+10=35) is
        // still under the 40 threshold -- now it's the happiness gate specifically that blocks.
        vm.prank(alice);
        creatureNFT.feedCreature(tokenId);
        c = creatureNFT.getCreature(tokenId);
        assertEq(c.happiness, 35);

        uint8 minHappiness = creatureNFT.MIN_HAPPINESS_TO_LAY_EGG(); // read before pranking (see
        // _purchaseCommonCreature callers elsewhere for why: inlining this call as a vm.expectRevert
        // argument would itself consume the single-use vm.prank before layEgg ever runs.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CreatureNFT.CreatureUnhappy.selector, tokenId, 35, minHappiness));
        creatureNFT.layEgg(tokenId);

        // Wait for a little hunger to reopen feedCreature (it reverts on an already-full
        // creature), then feed again: happiness crosses back over 40 and laying is allowed.
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        creatureNFT.feedCreature(tokenId);
        c = creatureNFT.getCreature(tokenId);
        assertEq(c.happiness, 45);

        vm.prank(alice);
        creatureNFT.layEgg(tokenId); // succeeds now
    }

    function test_LayEgg_RevertsWhenStarving() public {
        uint256 tokenId = _purchaseCommonCreature(alice);
        vm.warp(block.timestamp + 10 hours);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CreatureNFT.CreatureStarving.selector, tokenId));
        creatureNFT.layEgg(tokenId);
    }

    function test_BreedCreatures_BurnsFeedAndIncrementsBreedCount() public {
        uint256 p1 = _purchaseCommonCreature(alice);
        uint256 p2 = _purchaseCommonCreature(alice);
        _giveFeed(alice, 1000 ether);
        vm.deal(alice, 1 ether);

        vm.prank(alice);
        uint256 eggId = creatureNFT.breedCreatures{value: 0.01 ether}(p1, p2);

        assertEq(eggNFT.ownerOf(eggId), alice);
        assertEq(creatureNFT.getBreedCount(p1), 1);
        assertEq(creatureNFT.getBreedCount(p2), 1);
        assertEq(feedToken.balanceOf(alice), 950 ether); // 1000 - 50 (first breed cost)
    }

    function test_BreedCreatures_RevertsAtMaxBreedCount() public {
        uint256 p1 = _purchaseCommonCreature(alice);
        uint256 p2 = _purchaseCommonCreature(alice);
        _giveFeed(alice, 1_000_000 ether);
        vm.deal(alice, 10 ether);

        for (uint256 i = 0; i < 7; i++) {
            vm.prank(alice);
            creatureNFT.breedCreatures{value: 0.01 ether}(p1, p2);
        }

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CreatureNFT.MaxBreedCountReached.selector, p1));
        creatureNFT.breedCreatures{value: 0.01 ether}(p1, p2);
    }

    function test_BreedCreatures_RevertsForDifferentOwners() public {
        uint256 p1 = _purchaseCommonCreature(alice);
        uint256 p2 = _purchaseCommonCreature(bob);
        _giveFeed(alice, 1000 ether);
        vm.deal(alice, 1 ether);

        vm.prank(alice);
        vm.expectRevert(CreatureNFT.NotCreatureOwner.selector);
        creatureNFT.breedCreatures{value: 0.01 ether}(p1, p2);
    }

    function test_BreedCreatures_RevertsOnSelfBreed() public {
        uint256 p1 = _purchaseCommonCreature(alice);
        _giveFeed(alice, 1000 ether);
        vm.deal(alice, 1 ether);

        vm.prank(alice);
        vm.expectRevert(CreatureNFT.CannotBreedWithSelf.selector);
        creatureNFT.breedCreatures{value: 0.01 ether}(p1, p1);
    }

    function test_MintFromEgg_OnlyCallableByEggNFT() public {
        vm.prank(alice);
        vm.expectRevert("only EggNFT");
        creatureNFT.mintFromEgg(alice, 0, 1, 50);
    }

    function test_PurchaseCreature_UncommonAndRareTiersPriced() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        uint256 uncommon = creatureNFT.purchaseCreature{value: 0.08 ether}(2);
        assertEq(creatureNFT.getRarity(uncommon), 2);

        vm.deal(bob, 1 ether);
        vm.prank(bob);
        uint256 rare = creatureNFT.purchaseCreature{value: 0.25 ether}(3);
        assertEq(creatureNFT.getRarity(rare), 3);
    }

    function test_BreedCreatures_RevertsOnInsufficientArb() public {
        uint256 p1 = _purchaseCommonCreature(alice);
        uint256 p2 = _purchaseCommonCreature(alice);
        _giveFeed(alice, 1000 ether);
        vm.deal(alice, 1 ether);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CreatureNFT.InsufficientPayment.selector, 0.01 ether, 0.005 ether));
        creatureNFT.breedCreatures{value: 0.005 ether}(p1, p2);
    }

    function test_BreedCreatures_RefundsExcessArb() public {
        uint256 p1 = _purchaseCommonCreature(alice);
        uint256 p2 = _purchaseCommonCreature(alice);
        _giveFeed(alice, 1000 ether);
        vm.deal(alice, 1 ether);
        uint256 balanceBefore = alice.balance;

        vm.prank(alice);
        creatureNFT.breedCreatures{value: 0.05 ether}(p1, p2);

        assertEq(alice.balance, balanceBefore - 0.01 ether);
    }

    function test_FeedCreature_RevertsForDeadCreature() public {
        uint256 tokenId = _purchaseCommonCreature(alice);
        vm.warp(block.timestamp + 10 hours); // hunger reaches 0
        creatureNFT.checkStarvation(tokenId); // marks hungerZeroSince
        vm.warp(block.timestamp + 24 hours + 1); // grace period elapses
        creatureNFT.checkStarvation(tokenId); // kills the creature
        assertFalse(creatureNFT.isAlive(tokenId));

        _giveFeed(alice, 100 ether);
        vm.prank(alice);
        vm.expectRevert(); // ownerOf reverts on burned token before CreatureDead check is reached
        creatureNFT.feedCreature(tokenId);
    }

    function test_PurchaseCreature_SpeciesStaysWithinItsTierRange() public {
        uint8 speciesPerTier = creatureNFT.SPECIES_PER_TIER(); // read before pranking (see below)

        for (uint8 tier = 1; tier <= 3; tier++) {
            uint256 price = creatureNFT.shopPrice(tier); // read before pranking: evaluating this
            // inline as a call argument (e.g. `{value: creatureNFT.shopPrice(tier)}`) would
            // itself consume the single-use vm.prank before purchaseCreature ever runs.
            for (uint256 i = 0; i < 5; i++) {
                address buyer = makeAddr(string.concat("buyer", vm.toString(tier), vm.toString(i)));
                vm.deal(buyer, 1 ether);
                vm.prank(buyer);
                uint256 tokenId = creatureNFT.purchaseCreature{value: price}(tier);

                uint8 species = creatureNFT.getCreature(tokenId).species;
                uint8 tierBase = (tier - 1) * speciesPerTier;
                assertGe(species, tierBase);
                assertLt(species, tierBase + speciesPerTier);
            }
        }
    }

    function test_Interbreeding_ProducesMoreMutationsThanSameSpeciesBreeding() public {
        CreatureNFTHarness harness = new CreatureNFTHarness(admin, address(feedToken), treasury);

        uint256 sameSpeciesMutations;
        uint256 crossSpeciesMutations;
        uint256 trials = 200;

        for (uint256 i = 0; i < trials; i++) {
            uint8 same = harness.rollOffspringSpecies(2, 2, 1, i);
            if (same != 2) sameSpeciesMutations++;

            uint8 cross = harness.rollOffspringSpecies(2, 10, 1, i + 100_000);
            if (cross != 2 && cross != 10) crossSpeciesMutations++;
        }

        // Same-species breeding mutates ~20% of the time; interbreeding mutates ~60% of the
        // time. Assert the core claim (interbreeding produces clearly more novel species) with
        // generous tolerance around the expected rates for a 200-trial sample.
        assertGt(crossSpeciesMutations, sameSpeciesMutations);
        assertApproxEqAbs(sameSpeciesMutations, 40, 25);
        assertApproxEqAbs(crossSpeciesMutations, 120, 30);
    }
}

/// @dev Exposes CreatureNFT's internal species-roll logic for direct, deterministic-enough
///      statistical testing without needing a full breedCreatures integration per trial (breed
///      count caps at 7 per creature, so brute-forcing hundreds of trials through the real flow
///      would mean minting hundreds of creature pairs just to sample the RNG).
contract CreatureNFTHarness is CreatureNFT {
    constructor(address admin, address feedTokenAddress, address treasuryAddress)
        CreatureNFT(admin, feedTokenAddress, treasuryAddress)
    {}

    function rollOffspringSpecies(uint8 species1, uint8 species2, uint8 offspringRarity, uint256 nonce)
        external
        view
        returns (uint8)
    {
        return _rollOffspringSpecies(species1, species2, offspringRarity, nonce);
    }
}
