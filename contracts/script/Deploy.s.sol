// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {FeedToken} from "../src/FeedToken.sol";
import {EggNFT} from "../src/EggNFT.sol";
import {CreatureNFT} from "../src/CreatureNFT.sol";
import {Marketplace} from "../src/Marketplace.sol";

/// @notice Deploys all four EggFarm Legends contracts and wires up their cross-references.
///         Usage:
///           forge script script/Deploy.s.sol:Deploy \
///             --rpc-url arbitrum_sepolia --broadcast --verify -vvvv
contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address treasury = vm.envOr("TREASURY_ADDRESS", deployer);
        address backendSigner = vm.envOr("BACKEND_SIGNER_ADDRESS", deployer);

        vm.startBroadcast(deployerKey);

        FeedToken feedToken = new FeedToken(deployer);
        EggNFT eggNFT = new EggNFT(deployer, address(feedToken), treasury);
        CreatureNFT creatureNFT = new CreatureNFT(deployer, address(feedToken), treasury);
        Marketplace marketplace = new Marketplace(deployer);

        // Wire circular references.
        eggNFT.setCreatureNFT(address(creatureNFT));
        creatureNFT.setEggNFT(address(eggNFT));

        // CreatureNFT burns FEED on feeding/breeding; EggNFT burns FEED on tendEgg.
        feedToken.grantRole(feedToken.BURNER_ROLE(), address(creatureNFT));
        feedToken.grantRole(feedToken.BURNER_ROLE(), address(eggNFT));
        // Backend Task Service signer mints FEED rewards.
        feedToken.grantRole(feedToken.MINTER_ROLE(), backendSigner);
        // Backend RNG service is also allowed to lay eggs directly (analytics / anti-cheat path).
        eggNFT.grantRole(eggNFT.GAME_CONTROLLER_ROLE(), backendSigner);

        // Marketplace accepts both NFT types.
        marketplace.setAllowedContract(address(eggNFT), true);
        marketplace.setAllowedContract(address(creatureNFT), true);

        vm.stopBroadcast();

        console.log("FeedToken:    ", address(feedToken));
        console.log("EggNFT:       ", address(eggNFT));
        console.log("CreatureNFT:  ", address(creatureNFT));
        console.log("Marketplace:  ", address(marketplace));
    }
}
