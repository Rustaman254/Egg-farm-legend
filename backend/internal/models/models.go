// Package models holds the DB-row types shared across services and API handlers.
package models

import "time"

type Player struct {
	WalletAddress     string     `json:"walletAddress"`
	DisplayName       *string    `json:"displayName,omitempty"`
	FeedBalanceCached string     `json:"feedBalanceCached"` // decimal string, 18 decimals
	LastLoginAt       *time.Time `json:"lastLoginAt,omitempty"`
	LoginStreakDays   int        `json:"loginStreakDays"`
}

type Creature struct {
	TokenID         int64      `json:"tokenId"`
	OwnerAddress    string     `json:"ownerAddress"`
	Species         int16      `json:"species"`
	Rarity          int16      `json:"rarity"`
	BreedCount      int16      `json:"breedCount"`
	Happiness       int16      `json:"happiness"`
	CareScore       int        `json:"careScore"`
	BirthTime       time.Time  `json:"birthTime"`
	LastFedAt       time.Time  `json:"lastFedAt"`
	LastEggAt       *time.Time `json:"lastEggAt,omitempty"`
	IsDead          bool       `json:"isDead"`
	HungerZeroSince *time.Time `json:"hungerZeroSince,omitempty"`
	// Hunger is derived, not stored: 10%/hour decay since LastFedAt, floored at 0.
	Hunger int `json:"hunger"`
	// Abilities: ability keys this creature currently has (see AbilityCatalog); resolved to full
	// Ability objects client-side via GET /api/abilities so this payload stays small.
	Abilities []string `json:"abilities,omitempty"`
	// MaturesAt/IsMature are derived, not stored: BirthTime + MaturationDuration(Rarity), mirroring
	// CreatureNFT.sol's maturesAt/isMature exactly. Until mature a creature can be fed, battled,
	// and bred, but CreatureNFT._update reverts on any real transfer, so it can't be listed on the
	// Marketplace -- see the "juvenile" design note on CreatureNFT.sol.
	MaturesAt time.Time `json:"maturesAt"`
	IsMature  bool      `json:"isMature"`
	// Nickname is this individual's own name (Pokemon-nickname-style, e.g. "Prisma") -- auto-
	// generated at lay time (models.GenerateNickname), carried over from its egg on hatch, and
	// renameable by the owner. Species stays the "type"; Nickname is what makes it unique.
	Nickname *string `json:"nickname,omitempty"`
}

// MaturationDuration mirrors CreatureNFT.sol's maturationDuration(rarity): rarity hours (1h
// Common up to 5h Legendary). Keep in sync with the contract and the webapp's
// config/battleStats.ts maturationDurationMs.
func MaturationDuration(rarity int16) time.Duration {
	return time.Duration(rarity) * time.Hour
}

type Egg struct {
	TokenID      int64     `json:"tokenId"`
	OwnerAddress string    `json:"ownerAddress"`
	Rarity       int16     `json:"rarity"`
	Species      int16     `json:"species"`
	HatchTime    time.Time `json:"hatchTime"`
	Parent1      *int64    `json:"parent1,omitempty"`
	Parent2      *int64    `json:"parent2,omitempty"`
	IsRotten     bool      `json:"isRotten"`
	IsHatched    bool      `json:"isHatched"`
	LaidAt       time.Time `json:"laidAt"`
	IsHatchable  bool      `json:"isHatchable"`
	// CareLevel is the incubation care (0-100) as of the last Incubation Service sweep or tend
	// event -- lazily accurate to within that sweep interval, not live-computed per request (see
	// EggNFT.getCareLevel() on-chain for the exact current value).
	CareLevel   int16      `json:"careLevel"`
	LastCaredAt *time.Time `json:"lastCaredAt,omitempty"`
	// Nickname: see Creature.Nickname -- an egg gets its name the moment it's laid and keeps it
	// through hatching, so "Chicken (Prisma)" is true from the egg stage onward.
	Nickname *string `json:"nickname,omitempty"`
}

type Task struct {
	ID          string `json:"id"`
	Title       string `json:"title"`
	Description string `json:"description"`
	TargetCount int    `json:"targetCount"`
	RewardFeed  string `json:"rewardFeed"`
}

type TaskProgress struct {
	TaskID            string     `json:"taskId"`
	Title             string     `json:"title"`
	Description       string     `json:"description"`
	Category          string     `json:"category"` // "game" | "ecosystem" | "partner"
	CreatorAddress    *string    `json:"creatorAddress,omitempty"`
	CheckType         string     `json:"checkType"`
	ContractAddress   *string    `json:"contractAddress,omitempty"`
	FunctionSignature *string    `json:"functionSignature,omitempty"`
	EventSignature    *string    `json:"eventSignature,omitempty"`
	ExpiresAt         *time.Time `json:"expiresAt,omitempty"`
	CurrentCount      int        `json:"currentCount"`
	TargetCount       int        `json:"targetCount"`
	CompletedAt       *time.Time `json:"completedAt,omitempty"`
	RewardClaimed     bool       `json:"rewardClaimed"`
	RewardFeed        string     `json:"rewardFeed"`
	// FundedFeed is only meaningful for a partner task (CreatorAddress set): how much $FEED the
	// creator has paid to fund its reward pool so far. A built-in task's rewards are always
	// funded (the core game loop, not gated) so this stays 0/unused for those.
	FundedFeed string `json:"fundedFeed,omitempty"`
}

type Listing struct {
	ListingID     int64      `json:"listingId"`
	NFTContract   string     `json:"nftContract"`
	TokenID       int64      `json:"tokenId"`
	Kind          string     `json:"kind"` // "egg" | "creature"
	SellerAddress string     `json:"sellerAddress"`
	PriceWei      string     `json:"priceWei"`
	IsActive      bool       `json:"isActive"`
	ListedAt      time.Time  `json:"listedAt"`
	SoldAt        *time.Time `json:"soldAt,omitempty"`
	BuyerAddress  *string    `json:"buyerAddress,omitempty"`
	// Rarity/Species are joined in from the creatures/eggs cache for card art; nil only if the
	// listed item somehow isn't in our cache yet (shouldn't happen for items listed in-app).
	Rarity  *int16 `json:"rarity,omitempty"`
	Species *int16 `json:"species,omitempty"`
	// CareScore is nil for egg listings (eggs don't level) and populated for creature listings.
	CareScore *int `json:"careScore,omitempty"`
	// Happiness is nil for egg listings; populated for creature listings (see api.ConditionLabel).
	Happiness *int16 `json:"happiness,omitempty"`
	// Abilities is empty for egg listings; populated for creature listings.
	Abilities []string `json:"abilities,omitempty"`
	// Hot flags the single listing GetListings judges most in-demand right now (see
	// api.handleListListings) -- recent sales velocity for that species, falling back to rarity
	// when nothing's sold yet. Never set on a seller-scoped ("my listings") query.
	Hot bool `json:"hot,omitempty"`
	// Nickname: see Creature.Nickname.
	Nickname *string `json:"nickname,omitempty"`
}

// WalletEvent is one row of a player's generic wallet activity feed -- native-balance changes
// (Wallet Watcher) and marketplace trades (Marketplace Indexer). See
// migrations/0016_wallet_events.sql.
type WalletEvent struct {
	ID        int64     `json:"id"`
	Kind      string    `json:"kind"` // "balance_up" | "balance_down" | "listing_sold" | "listing_bought"
	Message   string    `json:"message"`
	AmountWei *string   `json:"amountWei,omitempty"`
	CreatedAt time.Time `json:"createdAt"`
}

// Species roster, matching CreatureNFT.sol's SPECIES_PER_TIER=8 species pool (index 0-39, 8 per
// rarity tier). "Animora" is the collective name for the whole roster (see the webapp's UI copy)
// -- these are the *species* (the type every individual of that species shares, like a Pokemon
// species name); each individual egg/creature also gets its own Nickname (see GenerateNickname)
// on top of this, e.g. "Chicken (Prisma)". Common starts with real, everyday egg-layers across
// several animal classes (not just birds), escalating through exotic real animals, reptiles and
// lesser myth, into full fantasy -- including a dedicated cross-species "mutant" archetype
// (Genesplice) for when breeding rolls a mutation (see GenerateMutantNickname).
var SpeciesNames = [40]string{
	// Common (rarity 1): everyday real egg-layers, several animal classes for variety
	"Chicken", "Duck", "Quail", "Goose", "Turkey", "Pigeon", "Frog", "Butterfly",
	// Uncommon (rarity 2): exotic real animals and genuine oddities
	"Peacock", "Ostrich", "Flamingo", "Platypus", "Echidna", "Seahorse", "Axolotl", "Cuttlefish",
	// Rare (rarity 3): reptiles, lesser myth, and the first Animora-original species
	"Komodo Dragon", "Cobra", "Crocodile", "Tortoise", "Cockatrice", "Flarepaw", "Aquadew", "Voltkit",
	// Epic (rarity 4): legendary beasts and evolved-feeling Animora originals
	"Phoenix", "Griffin", "Hydra", "Chimera", "Wyvern", "Blazehorn", "Frostbite", "Genesplice",
	// Legendary (rarity 5): cosmic/world myth and mystical-tier Animora originals
	"Void Dragon", "World Serpent", "Qilin", "Simurgh", "Aetheron", "Nebulisk", "Chronox", "Prismara",
}

func SpeciesName(species int16) string {
	if species < 0 || int(species) >= len(SpeciesNames) {
		return "Unknown"
	}
	return SpeciesNames[species]
}

const TotalSpeciesCount = len(SpeciesNames)

// DexEntry is one row of a player's species dex -- see migrations/0004_species_dex.sql.
type DexEntry struct {
	Species      int16      `json:"species"`
	Discovered   bool       `json:"discovered"`
	DiscoveredAt *time.Time `json:"discoveredAt,omitempty"`
	OwnedCount   int        `json:"ownedCount"`
}
