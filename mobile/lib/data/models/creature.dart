class Creature {
  final int tokenId;
  final String ownerAddress;
  final int species;
  final int rarity;
  final int breedCount;
  final int happiness;
  final int hunger;
  final int careScore;
  final List<String> abilities;
  final DateTime birthTime;
  final DateTime lastFedAt;
  final DateTime? lastEggAt;
  final bool isDead;

  const Creature({
    required this.tokenId,
    required this.ownerAddress,
    required this.species,
    required this.rarity,
    required this.breedCount,
    required this.happiness,
    required this.hunger,
    this.careScore = 0,
    this.abilities = const [],
    required this.birthTime,
    required this.lastFedAt,
    this.lastEggAt,
    this.isDead = false,
  });

  /// A creature has to actually be cared for to lay -- fed recently and reasonably happy (a
  /// farmer who lets happiness rot can't just keep cashing in eggs off a miserable creature).
  /// Mirrors webapp src/api/types.ts's canLayEgg/MIN_HAPPINESS_TO_LAY.
  static const minHappinessToLay = 40;

  bool get isStarving => hunger == 0;
  bool get canBreed => breedCount < 7;
  bool get canLayEgg =>
      !isDead &&
      hunger > 0 &&
      happiness >= minHappinessToLay &&
      (lastEggAt == null ||
          DateTime.now().difference(lastEggAt!).inHours >= 2);

  /// A rough "condition" readout for the market -- not a stat, just a legible signal so a buyer
  /// can tell a well-raised creature from a neglected one at a glance. Mirrors webapp's
  /// conditionLabel in src/api/types.ts.
  String get condition {
    final level = ((careScore / 20).floor() + 1).clamp(1, 50);
    final score = happiness * 0.6 + (level > 20 ? 20 : level) * 2;
    if (score < 25) return 'Neglected';
    if (score < 45) return 'Poor';
    if (score < 65) return 'Fair';
    if (score < 85) return 'Good';
    return 'Excellent';
  }

  Duration? get eggCooldownRemaining {
    if (lastEggAt == null) return null;
    final ready = lastEggAt!.add(const Duration(hours: 2));
    final remaining = ready.difference(DateTime.now());
    return remaining.isNegative ? null : remaining;
  }

  factory Creature.fromJson(Map<String, dynamic> json) {
    return Creature(
      tokenId: json['tokenId'] as int,
      ownerAddress: json['ownerAddress'] as String,
      species: json['species'] as int,
      rarity: json['rarity'] as int,
      breedCount: json['breedCount'] as int,
      happiness: json['happiness'] as int,
      hunger: json['hunger'] as int,
      careScore: json['careScore'] as int? ?? 0,
      abilities: (json['abilities'] as List<dynamic>? ?? []).cast<String>(),
      birthTime: DateTime.parse(json['birthTime'] as String),
      lastFedAt: DateTime.parse(json['lastFedAt'] as String),
      lastEggAt: json['lastEggAt'] != null ? DateTime.parse(json['lastEggAt'] as String) : null,
      isDead: json['isDead'] as bool? ?? false,
    );
  }

  Creature copyWith({int? happiness, int? hunger, DateTime? lastFedAt, DateTime? lastEggAt, int? breedCount}) {
    return Creature(
      tokenId: tokenId,
      ownerAddress: ownerAddress,
      species: species,
      rarity: rarity,
      breedCount: breedCount ?? this.breedCount,
      happiness: happiness ?? this.happiness,
      hunger: hunger ?? this.hunger,
      careScore: careScore,
      abilities: abilities,
      birthTime: birthTime,
      lastFedAt: lastFedAt ?? this.lastFedAt,
      lastEggAt: lastEggAt ?? this.lastEggAt,
      isDead: isDead,
    );
  }
}
