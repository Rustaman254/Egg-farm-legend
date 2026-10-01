package battle

import (
	"context"
	"fmt"

	"github.com/eggfarm/backend/internal/models"
)

// CombatMods is the combined effect of a creature's whole ability set, folded into one struct so
// simulate() doesn't need to know about the ability catalog at all -- just how to apply these.
type CombatMods struct {
	Lifesteal   float64
	Thorns      float64
	Berserker   bool
	FirstStrike bool
}

func combineAbilities(keys []string) (mods CombatMods, atkMult, defMult, hpMult float64) {
	atkMult, defMult, hpMult = 1, 1, 1
	for _, key := range keys {
		a, ok := models.AbilityCatalog[key]
		if !ok {
			continue
		}
		atkMult *= a.AtkMult
		defMult *= a.DefMult
		hpMult *= a.HPMult
		mods.Lifesteal += a.Lifesteal
		mods.Thorns += a.Thorns
		mods.Berserker = mods.Berserker || a.Berserker
		mods.FirstStrike = mods.FirstStrike || a.FirstStrike
	}
	if mods.Lifesteal > 0.75 {
		mods.Lifesteal = 0.75
	}
	if mods.Thorns > 0.5 {
		mods.Thorns = 0.5
	}
	return
}

// abilityKeys returns a creature's current ability keys, newest-rolled first. Empty for a wild
// PvE opponent (they're procedurally generated, never a real row in `creatures`) or a genesis
// creature minted before the ability system shipped.
func (s *Service) abilityKeys(ctx context.Context, tokenID int64) ([]string, error) {
	rows, err := s.db.Query(ctx, `
		SELECT ability_key FROM creature_abilities WHERE creature_token_id = $1 ORDER BY acquired_at DESC`, tokenID)
	if err != nil {
		return nil, fmt.Errorf("reading abilities for creature %d: %w", tokenID, err)
	}
	defer rows.Close()

	var keys []string
	for rows.Next() {
		var key string
		if err := rows.Scan(&key); err != nil {
			return nil, err
		}
		keys = append(keys, key)
	}
	return keys, rows.Err()
}

// statsWithAbilities applies a creature's ability multipliers on top of its base Stats() line.
func (s *Service) statsWithAbilities(ctx context.Context, tokenID int64, species, rarity, careScore int) (hp, atk, def int, mods CombatMods, keys []string, err error) {
	baseHP, baseAtk, baseDef := Stats(species, rarity, careScore)
	keys, err = s.abilityKeys(ctx, tokenID)
	if err != nil {
		return 0, 0, 0, CombatMods{}, nil, err
	}
	var atkMult, defMult, hpMult float64
	mods, atkMult, defMult, hpMult = combineAbilities(keys)
	hp = int(float64(baseHP) * hpMult)
	atk = int(float64(baseAtk) * atkMult)
	def = int(float64(baseDef) * defMult)
	return
}
