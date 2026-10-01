// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IEggNFT} from "./interfaces/IEggNFT.sol";
import {FeedToken} from "./FeedToken.sol";

/// @title CreatureNFT
/// @notice ERC-721 representing a live creature. Handles feeding, starvation/death, spontaneous
///         egg laying, and breeding. Hunger is computed lazily from `lastFed` (10%/hour decay)
///         rather than updated on-chain every hour, so no contract-side cron is needed; the
///         backend Hunger Service periodically calls `checkStarvation` to enforce the 24h death
///         rule and to send "your creature is hungry" push notifications off-chain.
/// @dev Randomness for egg laying / breeding genetics uses block data (prevrandao + timestamp +
///      tokenId + a per-creature nonce). This is adequate for a hackathon MVP but is NOT secure
///      against a miner/validator or a searcher simulating transactions; a production deployment
///      should replace `_random` with Chainlink VRF or an equivalent verifiable randomness feed.
contract CreatureNFT is ERC721, AccessControl, ReentrancyGuard {
    bytes32 public constant GAME_CONTROLLER_ROLE = keccak256("GAME_CONTROLLER_ROLE");

    uint8 public constant MAX_BREED_COUNT = 7;
    uint8 public constant MAX_RARITY = 5;
    /// Species pool: SPECIES_PER_TIER species per rarity tier (real egg-laying animals at the
    /// low end, escalating into mythical creatures at the high end -- see models.SpeciesNames
    /// in the backend / SPECIES_NAMES in the apps for the full roster). Species index therefore
    /// runs 0 to (MAX_RARITY * SPECIES_PER_TIER - 1); tier = species / SPECIES_PER_TIER.
    uint8 public constant SPECIES_PER_TIER = 8;
    uint32 public constant HUNGER_DECAY_PER_HOUR = 10; // 10% per hour
    uint32 public constant STARVATION_GRACE_PERIOD = 24 hours;
    uint32 public constant EGG_LAY_COOLDOWN = 2 hours;
    uint256 public constant FEED_COST_PER_MEAL = 5 ether; // 5 FEED (18 decimals), at 100% hunger deficit
    uint256 public constant BREED_ARB_COST = 0.01 ether;
    /// A creature must be at least this happy to lay -- "well taken care of", not just "not
    /// starving". Mirrors the webapp's MIN_HAPPINESS_TO_LAY exactly; that was previously only a
    /// disabled-button soft-check, this makes it a real on-chain requirement.
    uint8 public constant MIN_HAPPINESS_TO_LAY_EGG = 40;
    /// One-time happiness hit the first time hunger hits 0 in a given neglect episode (resets
    /// once fed again) -- see checkStarvation. Deliberately bigger than *two* feedCreature() +10
    /// bumps: the first feed only clears the hunger-starving gate (still can't lay, happiness
    /// stays under 40), so a lapse costs a real recovery period, not one instant feed.
    uint8 public constant NEGLECT_HAPPINESS_PENALTY = 25;

    struct Creature {
        uint8 species; // 0 to (MAX_RARITY*SPECIES_PER_TIER - 1); see SPECIES_PER_TIER above
        uint8 rarity; // 1-5
        uint16 breedCount; // 0-7
        uint8 happiness; // 0-100
        uint64 birthTime;
        uint64 lastFed; // hunger decays from this timestamp
        uint64 hungerZeroSince; // 0 while hunger > 0
        uint64 lastEggTime;
        bool isDead;
        // Juvenile period: a freshly-hatched/purchased/bred creature exists as a real NFT (so it
        // can be fed, battled, and bred like any other) but cannot be transferred -- and therefore
        // cannot be listed on the Marketplace, which escrows via safeTransferFrom -- until
        // maturesAt. See maturationDuration() and isMature().
        uint64 maturesAt;
    }

    FeedToken public immutable feedToken;
    IEggNFT public eggNFT;
    address public treasury;

    uint256 private _nextTokenId = 1;
    uint256 private _nonce;
    mapping(uint256 => Creature) private _creatures;

    // Shop price per rarity tier (index 1-3 usable, 0 unused). Only common/uncommon/rare
    // creatures are directly purchasable; epic/legendary only come from breeding or eggs.
    mapping(uint8 => uint256) public shopPrice;

    /// Fires on every creature mint (shop purchase or egg hatch) with the full state a backend
    /// indexer needs to create its Postgres row -- unlike CreaturePurchased, which only covers
    /// the shop path, this is emitted unconditionally from _mintCreature.
    event CreatureMinted(uint256 indexed tokenId, address indexed owner, uint8 species, uint8 rarity);
    event CreaturePurchased(uint256 indexed tokenId, address indexed owner, uint8 rarity, uint8 species);
    event CreatureFed(uint256 indexed tokenId, uint64 newLastFed, uint8 happiness);
    event CreatureStarved(uint256 indexed tokenId);
    event EggLaidBySpontaneous(uint256 indexed creatureId, uint256 indexed eggTokenId);
    event CreaturesBred(uint256 indexed parent1, uint256 indexed parent2, uint256 indexed eggTokenId);

    error CreatureDead(uint256 tokenId);
    error NotCreatureOwner();
    error CreatureStarving(uint256 tokenId);
    error EggLayOnCooldown(uint256 readyAt);
    error MaxBreedCountReached(uint256 tokenId);
    error CannotBreedWithSelf();
    error InsufficientPayment(uint256 required, uint256 sent);
    error InvalidRarityTier();
    error EggContractNotSet();
    error CreatureNotMature(uint256 tokenId, uint64 maturesAt);
    error CreatureNotHungry(uint256 tokenId);
    error CreatureUnhappy(uint256 tokenId, uint8 happiness, uint8 required);

    constructor(address admin, address feedTokenAddress, address treasuryAddress)
        ERC721("EggFarm Creature", "CREATURE")
    {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GAME_CONTROLLER_ROLE, admin);
        feedToken = FeedToken(feedTokenAddress);
        treasury = treasuryAddress;

        shopPrice[1] = 0.02 ether; // Common
        shopPrice[2] = 0.08 ether; // Uncommon
        shopPrice[3] = 0.25 ether; // Rare
    }

    /// @notice One-time wiring of the EggNFT contract address (deploy-time circular dependency).
    function setEggNFT(address eggNFTAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        eggNFT = IEggNFT(eggNFTAddress);
    }

    // ---------------------------------------------------------------------
    // Primary sale (shop)
    // ---------------------------------------------------------------------

    function purchaseCreature(uint8 rarityTier) external payable nonReentrant returns (uint256 tokenId) {
        uint256 price = shopPrice[rarityTier];
        if (price == 0) revert InvalidRarityTier();
        if (msg.value < price) revert InsufficientPayment(price, msg.value);

        uint8 species = _randomSpeciesForRarity(rarityTier, _nextNonce());
        tokenId = _mintCreature(msg.sender, species, rarityTier, 50);

        (bool sent,) = treasury.call{value: msg.value}("");
        require(sent, "treasury transfer failed");

        emit CreaturePurchased(tokenId, msg.sender, rarityTier, species);
    }

    /// @notice Mint a creature hatched from an egg. Only callable by EggNFT.
    function mintFromEgg(address to, uint8 species, uint8 rarity, uint8 startingHappiness)
        external
        returns (uint256 tokenId)
    {
        require(msg.sender == address(eggNFT), "only EggNFT");
        tokenId = _mintCreature(to, species, rarity, startingHappiness);
    }

    function _mintCreature(address to, uint8 species, uint8 rarity, uint8 startingHappiness)
        internal
        returns (uint256 tokenId)
    {
        tokenId = _nextTokenId++;
        _creatures[tokenId] = Creature({
            species: species,
            rarity: rarity,
            breedCount: 0,
            happiness: startingHappiness,
            birthTime: uint64(block.timestamp),
            lastFed: uint64(block.timestamp),
            hungerZeroSince: 0,
            lastEggTime: 0,
            isDead: false,
            maturesAt: uint64(block.timestamp) + maturationDuration(rarity)
        });
        _safeMint(to, tokenId);
        emit CreatureMinted(tokenId, to, species, rarity);
    }

    // ---------------------------------------------------------------------
    // Juvenile maturity
    // ---------------------------------------------------------------------

    /// @notice How long a creature of this rarity stays juvenile (non-transferable) after minting.
    ///         Mirrors the backend's models.MaturationDuration and the webapp's
    ///         config/battleStats.ts maturationDurationMs -- keep all three in sync.
    function maturationDuration(uint8 rarity) public pure returns (uint64) {
        return uint64(rarity) * 1 hours;
    }

    /// @notice True once a creature can be transferred (and therefore listed on the Marketplace).
    function isMature(uint256 tokenId) public view returns (bool) {
        return block.timestamp >= _creatures[tokenId].maturesAt;
    }

    /// @dev Blocks ordinary transfers (both a direct transferFrom and the Marketplace's escrow
    ///      safeTransferFrom) of a still-juvenile creature, while leaving minting (from == 0) and
    ///      burning (to == 0, e.g. starvation death) unaffected -- a juvenile creature can still be
    ///      fed, battled, bred, and can die of neglect; it just can't change hands or be listed
    ///      until it matures.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0) && !isMature(tokenId)) {
            revert CreatureNotMature(tokenId, _creatures[tokenId].maturesAt);
        }
        return super._update(to, tokenId, auth);
    }

    // ---------------------------------------------------------------------
    // Feeding / hunger / death
    // ---------------------------------------------------------------------

    /// @notice Feed the creature back up to full hunger. Costs FEED proportional to how hungry it
    ///         actually is -- a creature that's barely peckish costs little to top off, one that's
    ///         nearly starving costs the full FEED_COST_PER_MEAL, since the meal is doing more
    ///         work. Reverts if it isn't hungry at all: there's nothing to feed.
    function feedCreature(uint256 tokenId) external {
        Creature storage c = _creatures[tokenId];
        if (ownerOf(tokenId) != msg.sender) revert NotCreatureOwner();
        if (c.isDead) revert CreatureDead(tokenId);

        uint8 hunger = getHunger(tokenId);
        if (hunger >= 100) revert CreatureNotHungry(tokenId);

        uint256 deficit = 100 - hunger; // 1-100
        uint256 cost = (FEED_COST_PER_MEAL * deficit) / 100;
        feedToken.burnFeed(msg.sender, cost);

        c.lastFed = uint64(block.timestamp);
        c.hungerZeroSince = 0;
        c.happiness = c.happiness + 10 > 100 ? 100 : c.happiness + 10;

        emit CreatureFed(tokenId, c.lastFed, c.happiness);
    }

    /// @notice Lazily computed hunger (0-100). Decays 10%/hour since last feeding.
    function getHunger(uint256 tokenId) public view returns (uint8) {
        Creature memory c = _creatures[tokenId];
        if (c.isDead) return 0;
        uint256 elapsedHours = (block.timestamp - c.lastFed) / 1 hours;
        if (elapsedHours >= 10) return 0;
        return uint8(100 - elapsedHours * HUNGER_DECAY_PER_HOUR);
    }

    /// @notice Called by the backend Hunger Service cron (or anyone) to advance starvation
    ///         state. If hunger has been at 0 for >= 24h, the creature dies and its NFT burns.
    ///         Letting hunger hit zero at all also docks happiness once per neglect episode --
    ///         real, escalating stakes for neglect short of death, and what makes
    ///         MIN_HAPPINESS_TO_LAY_EGG a genuine "keep it cared for" gate rather than a
    ///         threshold every creature starts above and never drops below.
    function checkStarvation(uint256 tokenId) external {
        Creature storage c = _creatures[tokenId];
        if (c.isDead) return;

        if (getHunger(tokenId) == 0) {
            if (c.hungerZeroSince == 0) {
                c.hungerZeroSince = uint64(block.timestamp);
                c.happiness = c.happiness > NEGLECT_HAPPINESS_PENALTY ? c.happiness - NEGLECT_HAPPINESS_PENALTY : 0;
            } else if (block.timestamp - c.hungerZeroSince >= STARVATION_GRACE_PERIOD) {
                c.isDead = true;
                emit CreatureStarved(tokenId);
                _burn(tokenId);
            }
        } else {
            c.hungerZeroSince = 0;
        }
    }

    // ---------------------------------------------------------------------
    // Spontaneous egg laying
    // ---------------------------------------------------------------------

    /// @notice Owner-triggered egg lay. Egg rarity/rotten-ness follows the happiness-weighted
    ///         formula from the design doc. Only a healthy, well-cared-for creature can lay: not
    ///         starving, happiness at or above MIN_HAPPINESS_TO_LAY_EGG (a creature you've kept
    ///         fed and happy, not just alive), and past the 2h cooldown since it last laid.
    function layEgg(uint256 tokenId) external nonReentrant returns (uint256 eggTokenId) {
        if (address(eggNFT) == address(0)) revert EggContractNotSet();
        Creature storage c = _creatures[tokenId];
        if (ownerOf(tokenId) != msg.sender) revert NotCreatureOwner();
        if (c.isDead) revert CreatureDead(tokenId);
        if (getHunger(tokenId) == 0) revert CreatureStarving(tokenId);
        if (c.happiness < MIN_HAPPINESS_TO_LAY_EGG) revert CreatureUnhappy(tokenId, c.happiness, MIN_HAPPINESS_TO_LAY_EGG);
        if (c.lastEggTime != 0 && block.timestamp < c.lastEggTime + EGG_LAY_COOLDOWN) {
            revert EggLayOnCooldown(c.lastEggTime + EGG_LAY_COOLDOWN);
        }

        c.lastEggTime = uint64(block.timestamp);

        (uint8 eggRarity, bool isRotten) = _rollEggOutcome(c.rarity, c.happiness, _nextNonce());
        uint8 eggSpecies = isRotten ? c.species : _randomSpeciesForRarity(eggRarity, _nextNonce());
        uint64 hatchTime = uint64(block.timestamp) + _hatchDuration(eggRarity);

        eggTokenId = eggNFT.layEgg(msg.sender, eggRarity, eggSpecies, hatchTime, tokenId, 0, isRotten);
        emit EggLaidBySpontaneous(tokenId, eggTokenId);
    }

    /// @dev Happiness-weighted rarity-up / rotten-egg roll, matching the design doc:
    ///      happiness > 80  -> 25% rare-up,  5% rotten
    ///      happiness < 30  ->  5% rare-up, 25% rotten
    ///      otherwise       -> 20% rare-up, 10% rotten
    function _rollEggOutcome(uint8 parentRarity, uint8 happiness, uint256 nonce)
        internal
        view
        returns (uint8 eggRarity, bool isRotten)
    {
        uint8 rareChance;
        uint8 rottenChance;
        if (happiness > 80) {
            rareChance = 25;
            rottenChance = 5;
        } else if (happiness < 30) {
            rareChance = 5;
            rottenChance = 25;
        } else {
            rareChance = 20;
            rottenChance = 10;
        }

        uint256 roll = (_random(nonce) % 100) + 1;
        if (roll <= rottenChance) {
            isRotten = true;
            eggRarity = parentRarity;
        } else if (roll <= rottenChance + rareChance) {
            eggRarity = parentRarity >= MAX_RARITY ? MAX_RARITY : parentRarity + 1;
        } else {
            eggRarity = parentRarity;
        }
    }

    function _hatchDuration(uint8 rarity) internal pure returns (uint64) {
        // 24h (common) up to 72h (legendary), matching the 24-72h spec range.
        return uint64(24 hours) + uint64(rarity - 1) * uint64(12 hours);
    }

    // ---------------------------------------------------------------------
    // Breeding
    // ---------------------------------------------------------------------

    function breedingCost(uint256 parent1, uint256 parent2) public view returns (uint256 feedCost) {
        uint16 maxBreeds = _creatures[parent1].breedCount > _creatures[parent2].breedCount
            ? _creatures[parent1].breedCount
            : _creatures[parent2].breedCount;
        // 50 * 2^breedCount FEED, capped at 15,300 FEED (matches the 50-15,300 spec range).
        uint256 cost = 50 ether * (2 ** maxBreeds);
        feedCost = cost > 15300 ether ? 15300 ether : cost;
    }

    function breedCreatures(uint256 parent1, uint256 parent2)
        external
        payable
        nonReentrant
        returns (uint256 eggTokenId)
    {
        if (address(eggNFT) == address(0)) revert EggContractNotSet();
        if (parent1 == parent2) revert CannotBreedWithSelf();
        if (ownerOf(parent1) != msg.sender || ownerOf(parent2) != msg.sender) revert NotCreatureOwner();

        Creature storage p1 = _creatures[parent1];
        Creature storage p2 = _creatures[parent2];
        if (p1.isDead) revert CreatureDead(parent1);
        if (p2.isDead) revert CreatureDead(parent2);
        if (p1.breedCount >= MAX_BREED_COUNT) revert MaxBreedCountReached(parent1);
        if (p2.breedCount >= MAX_BREED_COUNT) revert MaxBreedCountReached(parent2);
        if (msg.value < BREED_ARB_COST) revert InsufficientPayment(BREED_ARB_COST, msg.value);

        uint256 feedCost = breedingCost(parent1, parent2);
        feedToken.burnFeed(msg.sender, feedCost);

        p1.breedCount += 1;
        p2.breedCount += 1;

        uint8 offspringRarity = _rollOffspringRarity(p1.rarity, p2.rarity, _nextNonce());
        uint8 offspringSpecies = _rollOffspringSpecies(p1.species, p2.species, offspringRarity, _nextNonce());
        uint64 hatchTime = uint64(block.timestamp) + _hatchDuration(offspringRarity);

        eggTokenId = eggNFT.layEgg(msg.sender, offspringRarity, offspringSpecies, hatchTime, parent1, parent2, false);

        if (msg.value > BREED_ARB_COST) {
            (bool refunded,) = msg.sender.call{value: msg.value - BREED_ARB_COST}("");
            require(refunded, "refund failed");
        }
        (bool sent,) = treasury.call{value: BREED_ARB_COST}("");
        require(sent, "treasury transfer failed");

        emit CreaturesBred(parent1, parent2, eggTokenId);
    }

    /// @dev offspring_rarity = avg(parent ratities) + random(-1, +2), clamped to [1, 5].
    function _rollOffspringRarity(uint8 rarity1, uint8 rarity2, uint256 nonce) internal view returns (uint8) {
        int256 avg = (int256(uint256(rarity1)) + int256(uint256(rarity2))) / 2;
        int256 variance = int256(_random(nonce) % 4) - 1; // -1, 0, +1, +2
        int256 result = avg + variance;
        if (result < 1) result = 1;
        if (result > int256(uint256(MAX_RARITY))) result = int256(uint256(MAX_RARITY));
        return uint8(uint256(result));
    }

    /// @dev Interbreeding (crossing two different species) is rewarded with a much higher
    ///      mutation chance than breeding within the same species -- this is the actual
    ///      mechanic behind "interbreed to get more unique creatures": same-species pairs
    ///      mostly stay true to the line (80% inherit / 20% mutate), while cross-species pairs
    ///      are far more likely to roll something novel from the offspring's rarity tier rather
    ///      than simply inheriting either parent's species (40% inherit / 60% mutate).
    function _rollOffspringSpecies(uint8 species1, uint8 species2, uint8 offspringRarity, uint256 nonce)
        internal
        view
        returns (uint8)
    {
        bool interbred = species1 != species2;
        uint256 mutateChance = interbred ? 60 : 20;
        uint256 roll = _random(nonce) % 100;

        if (roll < mutateChance) {
            return _randomSpeciesForRarity(offspringRarity, nonce);
        }
        // Remaining odds split evenly between the two parents' species.
        uint256 remainder = _random(nonce + 1) % (100 - mutateChance);
        return remainder < (100 - mutateChance) / 2 ? species1 : species2;
    }

    /// @dev Species pool is MAX_RARITY*SPECIES_PER_TIER species, SPECIES_PER_TIER per rarity
    ///      tier (tier = rarity-1).
    function _randomSpeciesForRarity(uint8 rarity, uint256 nonce) internal view returns (uint8) {
        uint8 base = (rarity - 1) * SPECIES_PER_TIER;
        return base + uint8(_random(nonce) % SPECIES_PER_TIER);
    }

    function _nextNonce() internal returns (uint256) {
        return _nonce++;
    }

    function _random(uint256 nonce) internal view returns (uint256) {
        return uint256(
            keccak256(abi.encodePacked(block.prevrandao, block.timestamp, msg.sender, nonce, _nonce))
        );
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    function getCreature(uint256 tokenId) external view returns (Creature memory) {
        return _creatures[tokenId];
    }

    function getRarity(uint256 tokenId) external view returns (uint8) {
        return _creatures[tokenId].rarity;
    }

    function getBreedCount(uint256 tokenId) external view returns (uint16) {
        return _creatures[tokenId].breedCount;
    }

    function isAlive(uint256 tokenId) external view returns (bool) {
        return !_creatures[tokenId].isDead;
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
