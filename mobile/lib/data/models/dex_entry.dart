/// Species Dex entry -- discovered species stay in the dex forever, even if the player no
/// longer owns one (see backend's dex service), so `ownedCount` can be 0 on a discovered entry.
class DexEntry {
  final int species;
  final bool discovered;
  final String? discoveredAt;
  final int ownedCount;

  const DexEntry({
    required this.species,
    required this.discovered,
    this.discoveredAt,
    required this.ownedCount,
  });

  int get tier => species ~/ 8 + 1;

  factory DexEntry.fromJson(Map<String, dynamic> json) => DexEntry(
        species: json['species'] as int,
        discovered: json['discovered'] as bool? ?? false,
        discoveredAt: json['discoveredAt'] as String?,
        ownedCount: json['ownedCount'] as int? ?? 0,
      );
}
