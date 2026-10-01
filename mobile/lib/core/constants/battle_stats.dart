/// Pokemon-TCG-style HP/Attack/Defense. Must stay bit-for-bit identical to the backend's
/// internal/services/battle/stats.go and the webapp's src/config/battleStats.ts -- all three show
/// and fight with the same numbers, with no shared package possible across the Go/TS/Dart
/// boundary, so any change here needs a matching change in both of those.
class BattleStats {
  final int hp;
  final int attack;
  final int defense;
  const BattleStats({required this.hp, required this.attack, required this.defense});
}

const carePerLevel = 20;
const maxCreatureLevel = 50;

int levelForCareScore(int careScore) {
  final level = (careScore / carePerLevel).floor() + 1;
  if (level < 1) return 1;
  if (level > maxCreatureLevel) return maxCreatureLevel;
  return level;
}

int _hashSpecies(int species) {
  int seed = (species * 2654435761) & 0xFFFFFFFF;
  seed = (seed ^ (seed >> 13)) & 0xFFFFFFFF;
  return seed;
}

/// Species+rarity-only component, no care/level growth -- what a freshly hatched creature (or a
/// procedurally-generated wild PvE opponent, always level 1) starts at.
BattleStats baseStats(int species, int rarity) {
  final seed = _hashSpecies(species);
  final hpVariance = seed % 40;
  final atkVariance = (seed >> 8) % 30;
  final defVariance = (seed >> 16) % 30;
  return BattleStats(
    hp: 40 + rarity * 32 + hpVariance,
    attack: 8 + rarity * 14 + atkVariance,
    defense: 6 + rarity * 12 + defVariance,
  );
}

BattleStats battleStats(int species, int rarity, [int careScore = 0]) {
  final base = baseStats(species, rarity);
  final growth = levelForCareScore(careScore) - 1;
  return BattleStats(
    hp: base.hp + growth * 6,
    attack: base.attack + growth * 2,
    defense: base.defense + growth * 2,
  );
}

/// How much a creature eats per meal, in kg -- bigger/rarer creatures have a bigger appetite.
/// Mirrors webapp's src/config/battleStats.ts appetiteKg.
double appetiteKg(int rarity) => ((0.2 + rarity * 0.3) * 10).round() / 10;
