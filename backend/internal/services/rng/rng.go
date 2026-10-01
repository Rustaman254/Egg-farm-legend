// Package rng implements the server-authoritative Egg RNG Service described in the design doc.
//
// It mirrors CreatureNFT.sol's on-chain `_rollEggOutcome` / `_rollOffspringRarity` formulas
// exactly, so the two must be kept in sync. It exists off-chain for two reasons:
//  1. The Flutter app calls /api/eggs/preview before a player commits an on-chain layEgg() tx,
//     so it can show "predicted odds" without spending gas.
//  2. It gives the backend an independent computation to cross-check against emitted EggLaid
//     events for anti-cheat / analytics, since a compromised or forked client can't lie about
//     what the chain actually minted.
package rng

import (
	"crypto/rand"
	"math/big"
)

const MaxRarity = 5

type EggOutcome struct {
	Rarity   int  `json:"rarity"`
	IsRotten bool `json:"isRotten"`
}

type Odds struct {
	RareUpChancePct int `json:"rareUpChancePct"`
	RottenChancePct int `json:"rottenChancePct"`
	SameChancePct   int `json:"sameChancePct"`
}

// OddsForHappiness returns the egg-outcome probability breakdown for a creature with the given
// happiness (0-100), matching CreatureNFT.sol's _rollEggOutcome thresholds.
func OddsForHappiness(happiness int) Odds {
	var rare, rotten int
	switch {
	case happiness > 80:
		rare, rotten = 25, 5
	case happiness < 30:
		rare, rotten = 5, 25
	default:
		rare, rotten = 20, 10
	}
	return Odds{RareUpChancePct: rare, RottenChancePct: rotten, SameChancePct: 100 - rare - rotten}
}

// RollEggOutcome performs the actual weighted roll using a CSPRNG. Used only for the off-chain
// preview / practice-mode path -- the real mint always goes through the on-chain roll, which is
// authoritative.
func RollEggOutcome(parentRarity int, happiness int) (EggOutcome, error) {
	odds := OddsForHappiness(happiness)
	roll, err := randIntN(100) // 0-99
	if err != nil {
		return EggOutcome{}, err
	}
	roll++ // 1-100, matching the Solidity `(rand % 100) + 1` convention

	switch {
	case roll <= odds.RottenChancePct:
		return EggOutcome{Rarity: parentRarity, IsRotten: true}, nil
	case roll <= odds.RottenChancePct+odds.RareUpChancePct:
		return EggOutcome{Rarity: min(parentRarity+1, MaxRarity), IsRotten: false}, nil
	default:
		return EggOutcome{Rarity: parentRarity, IsRotten: false}, nil
	}
}

// RollOffspringRarity mirrors _rollOffspringRarity: avg(parents) + random(-1, +2), clamped [1,5].
func RollOffspringRarity(rarity1, rarity2 int) (int, error) {
	avg := (rarity1 + rarity2) / 2
	variance, err := randIntN(4) // 0..3 -> maps to -1..+2
	if err != nil {
		return 0, err
	}
	result := avg + variance - 1
	if result < 1 {
		result = 1
	}
	if result > MaxRarity {
		result = MaxRarity
	}
	return result, nil
}

func randIntN(n int64) (int, error) {
	v, err := rand.Int(rand.Reader, big.NewInt(n))
	if err != nil {
		return 0, err
	}
	return int(v.Int64()), nil
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
