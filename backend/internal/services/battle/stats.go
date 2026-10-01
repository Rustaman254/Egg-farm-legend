package battle

// CarePerLevel is how much care_score (bumped +2 per real CreatureFed event -- see
// gamestate.onCreatureFed -- or +10 per battle win, see recordBattleRow's battleWinCareBonus) a
// creature needs to gain one level: 10 feeds' (or 2 wins') worth per level.
const CarePerLevel = 20

// MaxLevel caps growth so care investment can't inflate stats forever.
const MaxLevel = 50

// LevelForCareScore turns a cumulative care_score into a level, 1-MaxLevel. Deliberately a pure
// function of care_score (never stored redundantly) so it can never drift out of sync with it.
func LevelForCareScore(careScore int) int {
	level := careScore/CarePerLevel + 1
	if level > MaxLevel {
		return MaxLevel
	}
	if level < 1 {
		return 1
	}
	return level
}

// Stats computes Pokemon-TCG-style HP/Attack/Defense from species+rarity+careScore. This must
// stay bit-for-bit identical to the webapp's src/config/battleStats.ts -- both sides show and
// fight with the same numbers, with no field trip to a shared package possible across the Go/TS
// boundary, so any change here needs a matching change there.
//
// Two components: a fixed base from species+rarity (like a real Pokemon's base stat line -- every
// creature of the same species+rarity starts identical), plus a growth bonus from care_score
// (like EVs/leveling -- how well *this specific creature* has actually been looked after). The
// growth bonus is deliberately large relative to the base-stat spread across rarity tiers: a
// Common creature fed consistently for long enough (high level) will out-stat a Legendary that's
// been neglected (level 1) -- care matters more than the roll you got at birth.
func Stats(species, rarity, careScore int) (hp, attack, defense int) {
	baseHP, baseAttack, baseDefense := BaseStats(species, rarity)
	level := LevelForCareScore(careScore)
	growth := level - 1
	hp = baseHP + growth*6
	attack = baseAttack + growth*2
	defense = baseDefense + growth*2
	return
}

// BaseStats is the species+rarity-only component of Stats, with no care/level growth applied --
// what a freshly-hatched creature starts at. Exposed separately so callers that only have
// species+rarity (no care_score yet, e.g. a wild opponent generated fresh for a duel) can use it
// directly.
func BaseStats(species, rarity int) (hp, attack, defense int) {
	seed := uint32(species) * 2654435761
	seed = seed ^ (seed >> 13)
	hpVariance := int(seed % 40)
	atkVariance := int((seed >> 8) % 30)
	defVariance := int((seed >> 16) % 30)
	hp = 40 + rarity*32 + hpVariance
	attack = 8 + rarity*14 + atkVariance
	defense = 6 + rarity*12 + defVariance
	return
}
