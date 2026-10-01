// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ICreatureNFT} from "./interfaces/ICreatureNFT.sol";
import {FeedToken} from "./FeedToken.sol";

/// @title EggNFT
/// @notice ERC-721 representing an unhatched egg. Eggs are minted either by the backend's
///         RNG service (spontaneous laying from a fed/happy creature) or by CreatureNFT itself
///         (breeding), both of which hold GAME_CONTROLLER_ROLE. Rotten eggs can never hatch.
///
/// @dev Incubation care: an egg isn't just a countdown timer. Like a creature's hunger, each egg
///      carries a `careLevel` (0-100) that decays over time and must be topped up with
///      `tendEgg()`, or the egg spoils (goes rotten) before it ever gets to hatch. Rarer eggs
///      decay faster -- a Legendary egg is a bigger commitment than a Common one -- and
///      `hatchEgg()` refuses to run on a neglected egg (`careLevel < MIN_CARE_TO_HATCH`) even
///      after its timer is up, so hatching has a real prerequisite beyond "wait long enough".
///      A perfectly-tended egg also hatches into a happier creature (see CARE_HAPPINESS_BONUS).
contract EggNFT is ERC721, AccessControl {
    bytes32 public constant GAME_CONTROLLER_ROLE = keccak256("GAME_CONTROLLER_ROLE");

    uint32 public constant CARE_NEGLECT_GRACE_PERIOD = 12 hours;
    uint8 public constant MIN_CARE_TO_HATCH = 30;
    uint256 public constant TEND_COST_PER_RARITY = 3 ether; // 3 FEED * rarity (1-5)
    /// Flat ETH/ARB price per hour of remaining incubation skipped by speedUpHatch().
    uint256 public constant SPEEDUP_PRICE_PER_HOUR = 0.001 ether;

    address public treasury;

    struct Egg {
        uint8 rarity; // 1-5
        uint8 species; // index into the species pool, resolved on hatch
        uint64 hatchTime; // unix timestamp when hatching becomes possible
        uint256 parent1; // 0 if laid spontaneously (not bred)
        uint256 parent2; // 0 if laid spontaneously (not bred)
        bool isRotten;
        uint8 careLevel; // 0-100, decays over time; tendEgg() resets it to 100
        uint64 lastCaredAt; // timestamp care was last topped up (laid_at, or last tend)
        uint64 careZeroSince; // 0 while careLevel > 0; else when it first hit 0
    }

    uint256 private _nextTokenId = 1;
    mapping(uint256 => Egg) private _eggs;
    ICreatureNFT public creatureNFT;
    FeedToken public immutable feedToken;

    event EggLaid(uint256 indexed tokenId, address indexed owner, uint8 rarity, uint8 species, bool isRotten);
    event EggHatched(uint256 indexed tokenId, uint256 indexed creatureId, uint8 startingHappiness);
    event EggDiscarded(uint256 indexed tokenId);
    event EggTended(uint256 indexed tokenId, address indexed owner, uint8 careLevel);
    event EggSpoiled(uint256 indexed tokenId);
    event EggHatchSpedUp(uint256 indexed tokenId, address indexed owner, uint64 newHatchTime, uint256 hoursSkipped);

    error EggNotReady(uint256 hatchTime, uint256 currentTime);
    error EggIsRotten(uint256 tokenId);
    error EggNotRotten(uint256 tokenId);
    error EggCareTooLow(uint256 tokenId, uint8 careLevel, uint8 required);
    error NotEggOwner();
    error CreatureContractNotSet();
    error EggAlreadyHatchable(uint256 tokenId);
    error InsufficientPayment(uint256 required, uint256 sent);

    constructor(address admin, address feedTokenAddress, address treasuryAddress) ERC721("EggFarm Egg", "EGG") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GAME_CONTROLLER_ROLE, admin);
        feedToken = FeedToken(feedTokenAddress);
        treasury = treasuryAddress;
    }

    /// @notice One-time wiring of the CreatureNFT contract address (deploy-time circular
    ///         dependency: CreatureNFT needs EggNFT's address and vice versa).
    function setCreatureNFT(address creatureNFTAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        creatureNFT = ICreatureNFT(creatureNFTAddress);
        _grantRole(GAME_CONTROLLER_ROLE, creatureNFTAddress);
    }

    function layEgg(
        address to,
        uint8 rarity,
        uint8 species,
        uint64 hatchTime,
        uint256 parent1,
        uint256 parent2,
        bool isRotten
    ) external onlyRole(GAME_CONTROLLER_ROLE) returns (uint256 tokenId) {
        tokenId = _nextTokenId++;
        _eggs[tokenId] = Egg({
            rarity: rarity,
            species: species,
            hatchTime: hatchTime,
            parent1: parent1,
            parent2: parent2,
            isRotten: isRotten,
            careLevel: 100,
            lastCaredAt: uint64(block.timestamp),
            careZeroSince: 0
        });
        _safeMint(to, tokenId);
        emit EggLaid(tokenId, to, rarity, species, isRotten);
    }

    // ---------------------------------------------------------------------
    // Incubation care
    // ---------------------------------------------------------------------

    /// @dev Rarer eggs are more demanding: care drains faster the higher the rarity, so a
    ///      Legendary egg (rarity 5) needs roughly 2.5x the attention of a Common one (rarity 1)
    ///      over its (also longer) incubation window.
    function careDecayPerHour(uint8 rarity) public pure returns (uint8) {
        return 3 + rarity * 2; // rarity 1 -> 5%/hr, rarity 5 -> 13%/hr
    }

    /// @notice Lazily computed incubation care (0-100), decaying since lastCaredAt.
    function getCareLevel(uint256 tokenId) public view returns (uint8) {
        Egg memory egg = _eggs[tokenId];
        if (egg.isRotten) return 0;
        uint256 elapsedHours = (block.timestamp - egg.lastCaredAt) / 1 hours;
        uint256 decayed = elapsedHours * careDecayPerHour(egg.rarity);
        if (decayed >= 100) return 0;
        return uint8(100 - decayed);
    }

    /// @notice Top up an egg's care to 100. Costs FEED scaled by rarity (rarer eggs cost more to
    ///         keep warm). Anyone can neglect an egg into rotting; only the owner can tend it.
    function tendEgg(uint256 tokenId) external {
        if (ownerOf(tokenId) != msg.sender) revert NotEggOwner();
        Egg storage egg = _eggs[tokenId];
        if (egg.isRotten) revert EggIsRotten(tokenId);

        feedToken.burnFeed(msg.sender, TEND_COST_PER_RARITY * egg.rarity);

        egg.lastCaredAt = uint64(block.timestamp);
        egg.careZeroSince = 0;
        emit EggTended(tokenId, msg.sender, 100);
    }

    /// @notice Called by the backend Incubation Service cron (or anyone) to advance neglect
    ///         state. If care has been at 0 for >= 12h, the egg spoils (goes rotten) and can
    ///         never hatch -- mirrors CreatureNFT.checkStarvation's death mechanic.
    function checkEggCare(uint256 tokenId) external {
        Egg storage egg = _eggs[tokenId];
        if (egg.isRotten) return;

        if (getCareLevel(tokenId) == 0) {
            if (egg.careZeroSince == 0) {
                egg.careZeroSince = uint64(block.timestamp);
            } else if (block.timestamp - egg.careZeroSince >= CARE_NEGLECT_GRACE_PERIOD) {
                egg.isRotten = true;
                emit EggSpoiled(tokenId);
            }
        } else {
            egg.careZeroSince = 0;
        }
    }

    /// @notice Pay ETH/ARB to skip some or all of an egg's remaining incubation timer, at
    ///         SPEEDUP_PRICE_PER_HOUR per hour skipped (rounded up). Does not touch careLevel --
    ///         a sped-up egg still needs MIN_CARE_TO_HATCH to actually hatch once its timer hits.
    function speedUpHatch(uint256 tokenId) external payable {
        if (ownerOf(tokenId) != msg.sender) revert NotEggOwner();
        Egg storage egg = _eggs[tokenId];
        if (egg.isRotten) revert EggIsRotten(tokenId);
        if (block.timestamp >= egg.hatchTime) revert EggAlreadyHatchable(tokenId);

        uint256 remaining = egg.hatchTime - block.timestamp;
        uint256 hoursRemaining = (remaining + 1 hours - 1) / 1 hours; // round up to a whole hour
        uint256 cost = hoursRemaining * SPEEDUP_PRICE_PER_HOUR;
        if (msg.value < cost) revert InsufficientPayment(cost, msg.value);

        egg.hatchTime = uint64(block.timestamp);

        if (msg.value > cost) {
            (bool refunded,) = msg.sender.call{value: msg.value - cost}("");
            require(refunded, "refund failed");
        }
        (bool sent,) = treasury.call{value: cost}("");
        require(sent, "treasury transfer failed");

        emit EggHatchSpedUp(tokenId, msg.sender, egg.hatchTime, hoursRemaining);
    }

    // ---------------------------------------------------------------------
    // Hatching
    // ---------------------------------------------------------------------

    /// @notice Hatch a ready, non-rotten egg into a live creature owned by the caller. Requires
    ///         careLevel >= MIN_CARE_TO_HATCH even once the timer is up -- a neglected egg has to
    ///         be tended back up before it can hatch. A perfectly-tended egg (careLevel == 100)
    ///         hatches into a happier creature than a merely-adequate one.
    function hatchEgg(uint256 tokenId) external returns (uint256 creatureId) {
        if (ownerOf(tokenId) != msg.sender) revert NotEggOwner();
        if (address(creatureNFT) == address(0)) revert CreatureContractNotSet();

        Egg memory egg = _eggs[tokenId];
        if (egg.isRotten) revert EggIsRotten(tokenId);
        if (block.timestamp < egg.hatchTime) revert EggNotReady(egg.hatchTime, block.timestamp);

        uint8 care = getCareLevel(tokenId);
        if (care < MIN_CARE_TO_HATCH) revert EggCareTooLow(tokenId, care, MIN_CARE_TO_HATCH);

        uint8 startingHappiness = 50;
        if (care == 100) {
            startingHappiness = 80;
        } else if (care >= 70) {
            startingHappiness = 65;
        }

        delete _eggs[tokenId];
        _burn(tokenId);

        creatureId = creatureNFT.mintFromEgg(msg.sender, egg.species, egg.rarity, startingHappiness);
        emit EggHatched(tokenId, creatureId, startingHappiness);
    }

    /// @notice Discard a rotten egg (it can never hatch) to clean up inventory.
    function discardRottenEgg(uint256 tokenId) external {
        if (ownerOf(tokenId) != msg.sender) revert NotEggOwner();
        if (!_eggs[tokenId].isRotten) revert EggNotRotten(tokenId);
        delete _eggs[tokenId];
        _burn(tokenId);
        emit EggDiscarded(tokenId);
    }

    function getEggInfo(uint256 tokenId) external view returns (Egg memory) {
        _requireOwned(tokenId);
        return _eggs[tokenId];
    }

    function isHatchable(uint256 tokenId) external view returns (bool) {
        Egg memory egg = _eggs[tokenId];
        return !egg.isRotten && block.timestamp >= egg.hatchTime && getCareLevel(tokenId) >= MIN_CARE_TO_HATCH;
    }

    /// @notice Cheap targeted read of just the rotten flag, for the backend Incubation Service
    ///         to check after calling checkEggCare() without decoding the whole Egg struct.
    function isEggRotten(uint256 tokenId) external view returns (bool) {
        return _eggs[tokenId].isRotten;
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
