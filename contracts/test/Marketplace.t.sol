// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Deployers} from "./helpers/Deployers.sol";
import {Marketplace} from "../src/Marketplace.sol";

contract MarketplaceTest is Deployers {
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        _deployAll();
    }

    function _listCreature(address seller, uint256 tokenId, uint256 price) internal returns (uint256 listingId) {
        vm.prank(seller);
        creatureNFT.approve(address(marketplace), tokenId);
        vm.prank(seller);
        listingId = marketplace.listEgg(address(creatureNFT), tokenId, price);
    }

    function test_ListEgg_EscrowsNFT() public {
        uint256 tokenId = _purchaseCommonCreatureAndMature(alice);
        uint256 listingId = _listCreature(alice, tokenId, 0.15 ether);

        assertEq(creatureNFT.ownerOf(tokenId), address(marketplace));
        Marketplace.Listing memory listing = marketplace.getListing(listingId);
        assertEq(listing.seller, alice);
        assertEq(listing.price, 0.15 ether);
        assertTrue(listing.active);
    }

    function test_ListEgg_RevertsForDisallowedContract() public {
        vm.prank(alice);
        vm.expectRevert(Marketplace.ContractNotAllowed.selector);
        marketplace.listEgg(address(0xdead), 1, 1 ether);
    }

    function test_BuyEgg_PaysSellerMinusFeeAndTransfersNFT() public {
        uint256 tokenId = _purchaseCommonCreatureAndMature(alice);
        uint256 listingId = _listCreature(alice, tokenId, 0.15 ether);

        vm.deal(bob, 1 ether);
        uint256 aliceBalanceBefore = alice.balance;
        uint256 ownerBalanceBefore = admin.balance;

        vm.prank(bob);
        marketplace.buyEgg{value: 0.15 ether}(listingId);

        assertEq(creatureNFT.ownerOf(tokenId), bob);

        uint256 fee = (0.15 ether * 250) / 10_000; // 2.5%
        assertEq(alice.balance, aliceBalanceBefore + 0.15 ether - fee);
        assertEq(admin.balance, ownerBalanceBefore + fee);

        Marketplace.Listing memory listing = marketplace.getListing(listingId);
        assertFalse(listing.active);
    }

    function test_BuyEgg_RefundsExcessPayment() public {
        uint256 tokenId = _purchaseCommonCreatureAndMature(alice);
        uint256 listingId = _listCreature(alice, tokenId, 0.15 ether);

        vm.deal(bob, 1 ether);
        vm.prank(bob);
        marketplace.buyEgg{value: 0.2 ether}(listingId);

        assertEq(bob.balance, 1 ether - 0.15 ether);
    }

    function test_BuyEgg_RevertsOnUnderpayment() public {
        uint256 tokenId = _purchaseCommonCreatureAndMature(alice);
        uint256 listingId = _listCreature(alice, tokenId, 0.15 ether);

        vm.deal(bob, 1 ether);
        vm.prank(bob);
        vm.expectRevert();
        marketplace.buyEgg{value: 0.1 ether}(listingId);
    }

    function test_BuyEgg_RevertsForInactiveListing() public {
        uint256 tokenId = _purchaseCommonCreatureAndMature(alice);
        uint256 listingId = _listCreature(alice, tokenId, 0.15 ether);

        vm.prank(alice);
        marketplace.cancelListing(listingId);

        vm.deal(bob, 1 ether);
        vm.prank(bob);
        vm.expectRevert(Marketplace.ListingNotActive.selector);
        marketplace.buyEgg{value: 0.15 ether}(listingId);
    }

    function test_CancelListing_ReturnsNFTToSeller() public {
        uint256 tokenId = _purchaseCommonCreatureAndMature(alice);
        uint256 listingId = _listCreature(alice, tokenId, 0.15 ether);

        vm.prank(alice);
        marketplace.cancelListing(listingId);

        assertEq(creatureNFT.ownerOf(tokenId), alice);
    }

    function test_CancelListing_RevertsForNonSeller() public {
        uint256 tokenId = _purchaseCommonCreatureAndMature(alice);
        uint256 listingId = _listCreature(alice, tokenId, 0.15 ether);

        vm.prank(bob);
        vm.expectRevert(Marketplace.NotSeller.selector);
        marketplace.cancelListing(listingId);
    }
}
