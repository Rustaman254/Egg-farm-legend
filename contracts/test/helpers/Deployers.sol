// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {FeedToken} from "../../src/FeedToken.sol";
import {EggNFT} from "../../src/EggNFT.sol";
import {CreatureNFT} from "../../src/CreatureNFT.sol";
import {Marketplace} from "../../src/Marketplace.sol";

/// @notice Shared setup that wires the four contracts together exactly like script/Deploy.s.sol,
///         so tests exercise the same cross-contract role graph as production.
abstract contract Deployers is Test {
    FeedToken feedToken;
    EggNFT eggNFT;
    CreatureNFT creatureNFT;
    Marketplace marketplace;

    address admin = makeAddr("admin");
    address treasury = makeAddr("treasury");
    address backendSigner = makeAddr("backendSigner");

    function _deployAll() internal {
        vm.startPrank(admin);
        feedToken = new FeedToken(admin);
        eggNFT = new EggNFT(admin, address(feedToken), treasury);
        creatureNFT = new CreatureNFT(admin, address(feedToken), treasury);
        marketplace = new Marketplace(admin);

        eggNFT.setCreatureNFT(address(creatureNFT));
        creatureNFT.setEggNFT(address(eggNFT));

        feedToken.grantRole(feedToken.BURNER_ROLE(), address(creatureNFT));
        feedToken.grantRole(feedToken.BURNER_ROLE(), address(eggNFT));
        feedToken.grantRole(feedToken.MINTER_ROLE(), backendSigner);
        eggNFT.grantRole(eggNFT.GAME_CONTROLLER_ROLE(), backendSigner);

        marketplace.setAllowedContract(address(eggNFT), true);
        marketplace.setAllowedContract(address(creatureNFT), true);
        vm.stopPrank();
    }

    function _giveFeed(address to, uint256 amount) internal {
        vm.prank(backendSigner);
        feedToken.mintReward(to, amount);
    }

    function _purchaseCommonCreature(address buyer) internal returns (uint256 tokenId) {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        tokenId = creatureNFT.purchaseCreature{value: 0.02 ether}(1);
    }

    /// @notice Same as _purchaseCommonCreature, but warps past its juvenile period so it can
    ///         immediately be transferred/listed -- for tests that exercise the Marketplace or a
    ///         direct transfer rather than the maturity gate itself.
    function _purchaseCommonCreatureAndMature(address buyer) internal returns (uint256 tokenId) {
        tokenId = _purchaseCommonCreature(buyer);
        vm.warp(block.timestamp + creatureNFT.maturationDuration(1) + 1);
    }
}
