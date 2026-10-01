class Egg {
  final int tokenId;
  final String ownerAddress;
  final int rarity;
  final int species;
  final DateTime hatchTime;
  final int? parent1;
  final int? parent2;
  final bool isRotten;
  final bool isHatched;
  final DateTime laidAt;

  const Egg({
    required this.tokenId,
    required this.ownerAddress,
    required this.rarity,
    required this.species,
    required this.hatchTime,
    this.parent1,
    this.parent2,
    required this.isRotten,
    required this.isHatched,
    required this.laidAt,
  });

  bool get isHatchable => !isRotten && DateTime.now().isAfter(hatchTime);

  Duration get timeUntilHatch {
    final remaining = hatchTime.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool get isBred => parent1 != null && parent2 != null && parent2! > 0;

  factory Egg.fromJson(Map<String, dynamic> json) {
    return Egg(
      tokenId: json['tokenId'] as int,
      ownerAddress: json['ownerAddress'] as String,
      rarity: json['rarity'] as int,
      species: json['species'] as int,
      hatchTime: DateTime.parse(json['hatchTime'] as String),
      parent1: json['parent1'] as int?,
      parent2: json['parent2'] as int?,
      isRotten: json['isRotten'] as bool,
      isHatched: json['isHatched'] as bool,
      laidAt: DateTime.parse(json['laidAt'] as String),
    );
  }
}
