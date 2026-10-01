// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {BattleEscrow} from "../src/BattleEscrow.sol";

/// @notice Deploys BattleEscrow standalone -- it holds no reference to (and needs no changes in)
///         FeedToken/EggNFT/CreatureNFT/Marketplace, so this never touches their already-deployed
///         state. Usage:
///           forge script script/DeployBattleEscrow.s.sol:DeployBattleEscrow \
///             --rpc-url <...> --broadcast -vvvv
contract DeployBattleEscrow is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address treasury = vm.envOr("TREASURY_ADDRESS", deployer);
        address backendSigner = vm.envOr("BACKEND_SIGNER_ADDRESS", deployer);

        vm.startBroadcast(deployerKey);
        BattleEscrow escrow = new BattleEscrow(deployer, backendSigner, treasury);
        vm.stopBroadcast();

        console.log("BattleEscrow: ", address(escrow));
    }
}
