/** Pokemon-TCG-style HP/Attack/Defense, in two parts. Must stay bit-for-bit identical to the
 *  backend's internal/services/battle/stats.go -- both sides show and fight with the same
 *  numbers, with no shared package possible across the Go/TS boundary, so any change here needs
 *  a matching change there.
 *
 *  1. A fixed base from species+rarity (like a real Pokemon's base stat line -- every creature of
 *     the same species+rarity starts identical). Purely derived, no backend field needed.
 *  2. A growth bonus from care_score (fed via the backend, +2 per real feed) -- how well *this
 *     specific creature* has actually been looked after. Deliberately large relative to the
 *     base-stat spread across rarity tiers: a Common creature fed consistently for long enough
 *     will out-stat a Legendary that's been neglected -- care matters more than the rarity roll
 *     you got at birth. */
export interface BattleStats {
  hp: number
  attack: number
  defense: number
}

/** How much care_score one level costs (10 feeds/level), and the level cap. */
export const CARE_PER_LEVEL = 20
export const MAX_CREATURE_LEVEL = 50

export function levelForCareScore(careScore: number): number {
  const level = Math.floor(careScore / CARE_PER_LEVEL) + 1
  return Math.max(1, Math.min(MAX_CREATURE_LEVEL, level))
}

function hashSpecies(species: number): number {
  let seed = (species * 2654435761) >>> 0
  seed = (seed ^ (seed >>> 13)) >>> 0
  return seed
}

/** The species+rarity-only component, with no care/level growth applied -- what a freshly
 *  hatched creature (or a procedurally-generated wild PvE opponent, always level 1) starts at. */
export function baseStats(species: number, rarity: number): BattleStats {
  const seed = hashSpecies(species)
  const hpVariance = seed % 40
  const atkVariance = (seed >>> 8) % 30
  const defVariance = (seed >>> 16) % 30
  return {
    hp: 40 + rarity * 32 + hpVariance,
    attack: 8 + rarity * 14 + atkVariance,
    defense: 6 + rarity * 12 + defVariance,
  }
}

export function battleStats(species: number, rarity: number, careScore = 0): BattleStats {
  const base = baseStats(species, rarity)
  const growth = levelForCareScore(careScore) - 1
  return {
    hp: base.hp + growth * 6,
    attack: base.attack + growth * 2,
    defense: base.defense + growth * 2,
  }
}

/** How much a creature eats per meal, in kg -- bigger/rarer creatures have a bigger appetite. A
 *  Legendary genuinely costs more to keep fed than a Common, in real terms a player can picture
 *  (and shop for -- see the Feed Shop's kg-denominated bags), not just the flat $FEED burn the
 *  contract itself charges per feedCreature() call. Mirrors backend internal/models's
 *  AppetiteKg and mobile's battle_stats.dart appetiteKg. */
export function appetiteKg(rarity: number): number {
  return Math.round((0.2 + rarity * 0.3) * 10) / 10
}
