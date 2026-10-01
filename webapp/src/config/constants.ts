// Mirrors backend/internal/models.SpeciesNames and mobile/lib/core/constants/app_constants.dart
// -- keep all three in sync. 8 species per rarity tier (40 total, matching
// CreatureNFT.sol's SPECIES_PER_TIER). "Animora" is the collective name for the whole roster --
// this is the *species* (the type every individual shares, like a Pokemon species name); each
// individual egg/creature also gets its own generated Nickname on top of this (see
// displayName() below), e.g. "Chicken (Prisma)". Common starts with real, everyday egg-layers
// across several animal classes (not just birds), escalating through exotic real animals,
// reptiles/lesser myth, and into full fantasy -- including a dedicated cross-species "mutant"
// archetype (Genesplice) for when breeding rolls a mutation.
export const SPECIES_NAMES = [
  // Common: everyday real egg-layers, several animal classes for variety
  'Chicken', 'Duck', 'Quail', 'Goose', 'Turkey', 'Pigeon', 'Frog', 'Butterfly',
  // Uncommon: exotic real animals and genuine oddities
  'Peacock', 'Ostrich', 'Flamingo', 'Platypus', 'Echidna', 'Seahorse', 'Axolotl', 'Cuttlefish',
  // Rare: reptiles, lesser myth, and the first Animora-original species
  'Komodo Dragon', 'Cobra', 'Crocodile', 'Tortoise', 'Cockatrice', 'Flarepaw', 'Aquadew', 'Voltkit',
  // Epic: legendary beasts and evolved-feeling Animora originals
  'Phoenix', 'Griffin', 'Hydra', 'Chimera', 'Wyvern', 'Blazehorn', 'Frostbite', 'Genesplice',
  // Legendary: cosmic/world myth and mystical-tier Animora originals
  'Void Dragon', 'World Serpent', 'Qilin', 'Simurgh', 'Aetheron', 'Nebulisk', 'Chronox', 'Prismara',
] as const

export const SPECIES_EMOJI = [
  // Common
  '🐔', '🦆', '🐦', '🪿', '🦃', '🕊️', '🐸', '🦋',
  // Uncommon
  '🦚', '🦤', '🦩', '🦫', '🦔', '🐴🌊', '🦎💗', '🦑',
  // Rare
  '🦎', '🐍', '🐊', '🐢', '🐓🐍', '🔥🐾', '💧✨', '⚡🐾',
  // Epic
  '🐦‍🔥', '🦅🦁', '🐍🐍', '🦁🐐', '🐲', '🔥🐂', '❄️🦊', '🧬👾',
  // Legendary
  '🐉🌌', '🌍🐍', '🦄🐉', '🦚🔥', '🌌✨', '🐉✨', '⏳⚙️', '💎🧚',
] as const

export function speciesName(species: number): string {
  return SPECIES_NAMES[species] ?? 'Unknown'
}

export function speciesEmoji(species: number): string {
  return SPECIES_EMOJI[species] ?? '❓'
}

/** "Chicken (Prisma)" -- species is the type, nickname is what makes this individual unique.
 *  Falls back to just the species name for the rare case a nickname hasn't synced yet. */
export function displayName(species: number, nickname?: string): string {
  return nickname ? `${speciesName(species)} (${nickname})` : speciesName(species)
}

/** "Chicken's Egg" -- for an unhatched egg, leads with *what kind of egg it is* (Chicken's vs
 *  Dragon's) rather than the individual nickname, since that's the thing a buyer/owner actually
 *  needs to know before it hatches. */
export function eggDisplayName(species: number): string {
  return `${speciesName(species)}'s Egg`
}

export const RARITY_LABELS = ['', 'Common', 'Uncommon', 'Rare', 'Epic', 'Legendary'] as const
export const RARITY_STARS = ['', '⭐', '⭐⭐', '⭐⭐⭐', '⭐⭐⭐⭐', '⭐⭐⭐⭐⭐'] as const

export const RARITY_COLORS: Record<number, string> = {
  1: '#9E9BA8',
  2: '#35D07F',
  3: '#38A1FF',
  4: '#B565F3',
  5: '#FFB347',
}

/** The home dashboard's colorful category grid -- one tile per game section, mirroring the
 *  reference design's Originals/Slots/Live Casino/... tile row. */
export const CATEGORY_TILES = [
  { to: '/inventory', label: 'Eggs', icon: '🥚', color: 'var(--color-tile-violet)' },
  { to: '/tasks', label: 'Tasks', icon: '📋', color: 'var(--color-tile-orange)' },
  { to: '/farm', label: 'My Farm', icon: '🌾', color: 'var(--color-tile-gold)' },
  { to: '/breeding', label: 'Breeding', icon: '🧬', color: 'var(--color-tile-indigo)' },
  { to: '/battle', label: 'Battle Arena', icon: '⚔️', color: 'var(--color-tile-crimson)' },
  { to: '/marketplace?kind=creature', label: 'Animoras', icon: '🐉', color: 'var(--color-tile-maroon)' },
  { to: '/marketplace?kind=egg', label: 'Egg Market', icon: '🥚', color: 'var(--color-tile-navy)' },
  { to: '/marketplace', label: 'Marketplace', icon: '🏪', color: 'var(--color-tile-red)' },
  { to: '/collection', label: 'Species Dex', icon: '📖', color: 'var(--color-tile-green)' },
  { to: '/leaderboard', label: 'Leaderboard', icon: '🏆', color: 'var(--color-tile-teal)' },
] as const

/** Flat rate EggNFT.sol's speedUpHatch() charges per hour of incubation skipped -- must match
 *  SPEEDUP_PRICE_PER_HOUR exactly, it's not readable from a view function. */
export const HATCH_SPEEDUP_PRICE_PER_HOUR_ETH = 0.001

export const FEED_COST_PER_MEAL = 5
export const BREED_ARB_COST = 0.01
export const MAX_BREED_COUNT = 7
export const MAX_RARITY = 5
