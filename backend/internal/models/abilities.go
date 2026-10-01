package models

// Ability is a passive combat trait a creature can carry. Effects are plain stat multipliers plus
// a handful of named hooks the battle simulator special-cases (see internal/services/battle).
// The catalog is a fixed Go table rather than a DB-driven one -- abilities are game balance, not
// user content, so they ship with the backend the same way species names do.
type Ability struct {
	Key         string  `json:"key"`
	Name        string  `json:"name"`
	Description string  `json:"description"`
	MinRarity   int     `json:"minRarity"` // lowest creature rarity (1-5) this can be *rolled* on at genesis; mutation ignores this
	AtkMult     float64 `json:"atkMult"`
	DefMult     float64 `json:"defMult"`
	HPMult      float64 `json:"hpMult"`
	Lifesteal   float64 `json:"lifesteal,omitempty"`   // fraction of damage dealt that heals the attacker
	Thorns      float64 `json:"thorns,omitempty"`      // fraction of damage taken reflected back at the attacker
	Berserker   bool    `json:"berserker,omitempty"`   // +25% attack while below 30% HP
	FirstStrike bool    `json:"firstStrike,omitempty"` // this side's first landed hit deals double damage
}

// AbilityCatalog is every ability that can be rolled, keyed by its stable Key (also what's
// persisted in creature_abilities.ability_key). MinRarity gates genesis rolls only -- breeding
// mutation can hand a low-rarity offspring a higher-tier ability, which is the point: breeding is
// how a Common bloodline can eventually carry something a fresh Common egg never could.
var AbilityCatalog = map[string]Ability{
	"thick_hide":     {Key: "thick_hide", Name: "Thick Hide", Description: "Takes 20% less damage.", MinRarity: 1, AtkMult: 1, DefMult: 1.25, HPMult: 1},
	"swift_striker":  {Key: "swift_striker", Name: "Swift Striker", Description: "Hits 15% harder.", MinRarity: 1, AtkMult: 1.15, DefMult: 1, HPMult: 1},
	"iron_will":      {Key: "iron_will", Name: "Iron Will", Description: "20% more max HP.", MinRarity: 1, AtkMult: 1, DefMult: 1, HPMult: 1.2},
	"featherlight":   {Key: "featherlight", Name: "Featherlight", Description: "A touch faster and a touch tougher.", MinRarity: 1, AtkMult: 1.05, DefMult: 1.05, HPMult: 1},
	"venomous_bite":  {Key: "venomous_bite", Name: "Venomous Bite", Description: "Every hit carries a little extra bite.", MinRarity: 1, AtkMult: 1.1, DefMult: 0.95, HPMult: 1},
	"vampiric":       {Key: "vampiric", Name: "Vampiric", Description: "Heals for 25% of damage dealt.", MinRarity: 2, AtkMult: 1, DefMult: 1, HPMult: 1, Lifesteal: 0.25},
	"thorned_scales": {Key: "thorned_scales", Name: "Thorned Scales", Description: "Reflects 15% of damage taken back at the attacker.", MinRarity: 2, AtkMult: 1, DefMult: 1, HPMult: 1, Thorns: 0.15},
	"ambusher":       {Key: "ambusher", Name: "Ambusher", Description: "Its first landed hit deals double damage.", MinRarity: 2, AtkMult: 1, DefMult: 1, HPMult: 1, FirstStrike: true},
	"berserker_rage": {Key: "berserker_rage", Name: "Berserker Rage", Description: "Attacks 25% harder once below 30% HP.", MinRarity: 2, AtkMult: 1, DefMult: 1, HPMult: 1, Berserker: true},
	"glass_cannon":   {Key: "glass_cannon", Name: "Glass Cannon", Description: "35% harder hits, 15% less defense.", MinRarity: 3, AtkMult: 1.35, DefMult: 0.85, HPMult: 1},
	"fortress":       {Key: "fortress", Name: "Fortress", Description: "40% more defense, 10% less attack.", MinRarity: 3, AtkMult: 0.9, DefMult: 1.4, HPMult: 1},
	"regenerative":   {Key: "regenerative", Name: "Regenerative", Description: "30% more max HP.", MinRarity: 3, AtkMult: 1, DefMult: 1, HPMult: 1.3},
	"molten_core":    {Key: "molten_core", Name: "Molten Core", Description: "50% harder hits, 20% less defense.", MinRarity: 4, AtkMult: 1.5, DefMult: 0.8, HPMult: 1},
	"stormcaller":    {Key: "stormcaller", Name: "Stormcaller", Description: "Hits 25% harder and heals 15% of damage dealt.", MinRarity: 4, AtkMult: 1.25, DefMult: 1, HPMult: 1, Lifesteal: 0.15},
	"ancient_wisdom": {Key: "ancient_wisdom", Name: "Ancient Wisdom", Description: "30% more HP and 15% more defense.", MinRarity: 5, AtkMult: 1, DefMult: 1.15, HPMult: 1.3},
}

// AbilitiesForRarity returns every catalog ability a *genesis* (non-bred) creature of this rarity
// is eligible to roll -- MinRarity gated. Breeding mutation draws from the full catalog instead.
func AbilitiesForRarity(rarity int) []Ability {
	out := make([]Ability, 0, len(AbilityCatalog))
	for _, a := range AbilityCatalog {
		if a.MinRarity <= rarity {
			out = append(out, a)
		}
	}
	return out
}
