// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title FeedToken ($FEED)
/// @notice Unlimited-supply utility token. Minted as task/login/mini-game rewards by the
///         backend's MINTER_ROLE signer, burned by game contracts (feeding, breeding, crafting)
///         that hold BURNER_ROLE.
contract FeedToken is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    constructor(address admin) ERC20("EggFarm Feed", "FEED") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    /// @notice Mint reward tokens to a player. Called by the backend task/RNG service signer
    ///         after it has verified task completion, daily login, or mini-game results off-chain.
    function mintReward(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /// @notice Burn tokens from a player's balance to pay for feeding, breeding, or crafting.
    ///         Only callable by BURNER_ROLE holders (game contracts the player transacted with
    ///         directly, e.g. CreatureNFT.feedCreature), never by an arbitrary third party.
    function burnFeed(address from, uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(from, amount);
    }
}
