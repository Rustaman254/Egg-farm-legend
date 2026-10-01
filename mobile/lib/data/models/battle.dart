/// Battle Arena domain models: PvE/PvP duel results, the open+direct challenge board, arena
/// presence, and the ability catalog. Mirrors backend internal/services/battle.Result/
/// ChallengeSummary and webapp src/api/types.ts -- see those for the authoritative shape.
class BattleResult {
  final bool won;
  final int playerSpecies;
  final int playerLevel;
  final int playerHp;
  final int playerMaxHp;
  final List<String> playerAbilities;
  final int opponentSpecies;
  final int opponentRarity;
  final int opponentLevel;
  final int opponentHp;
  final int opponentMaxHp;
  final List<String> opponentAbilities;
  final int rounds;
  final List<String> log;
  final String rewardFeed;
  final int xpAwarded;
  final String? txHash;
  final String? wagerWei;
  final bool wagerWon;

  const BattleResult({
    required this.won,
    required this.playerSpecies,
    required this.playerLevel,
    required this.playerHp,
    required this.playerMaxHp,
    this.playerAbilities = const [],
    required this.opponentSpecies,
    required this.opponentRarity,
    required this.opponentLevel,
    required this.opponentHp,
    required this.opponentMaxHp,
    this.opponentAbilities = const [],
    required this.rounds,
    required this.log,
    required this.rewardFeed,
    required this.xpAwarded,
    this.txHash,
    this.wagerWei,
    this.wagerWon = false,
  });

  factory BattleResult.fromJson(Map<String, dynamic> json) {
    return BattleResult(
      won: json['won'] as bool,
      playerSpecies: json['playerSpecies'] as int,
      playerLevel: json['playerLevel'] as int,
      playerHp: json['playerHp'] as int,
      playerMaxHp: json['playerMaxHp'] as int,
      playerAbilities: (json['playerAbilities'] as List<dynamic>? ?? []).cast<String>(),
      opponentSpecies: json['opponentSpecies'] as int,
      opponentRarity: json['opponentRarity'] as int,
      opponentLevel: json['opponentLevel'] as int,
      opponentHp: json['opponentHp'] as int,
      opponentMaxHp: json['opponentMaxHp'] as int,
      opponentAbilities: (json['opponentAbilities'] as List<dynamic>? ?? []).cast<String>(),
      rounds: json['rounds'] as int,
      log: (json['log'] as List<dynamic>? ?? []).cast<String>(),
      rewardFeed: json['rewardFeed'] as String? ?? '0',
      xpAwarded: json['xpAwarded'] as int? ?? 0,
      txHash: json['txHash'] as String?,
      wagerWei: json['wagerWei'] as String?,
      wagerWon: json['wagerWon'] as bool? ?? false,
    );
  }
}

class BattleHistoryEntry {
  final int creatureTokenId;
  final int opponentSpecies;
  final int opponentRarity;
  final bool won;
  final String rewardFeed;
  final DateTime createdAt;

  const BattleHistoryEntry({
    required this.creatureTokenId,
    required this.opponentSpecies,
    required this.opponentRarity,
    required this.won,
    required this.rewardFeed,
    required this.createdAt,
  });

  factory BattleHistoryEntry.fromJson(Map<String, dynamic> json) {
    return BattleHistoryEntry(
      creatureTokenId: json['creatureTokenId'] as int,
      opponentSpecies: json['opponentSpecies'] as int,
      opponentRarity: json['opponentRarity'] as int,
      won: json['won'] as bool,
      rewardFeed: json['rewardFeed'] as String? ?? '0',
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class OnlinePlayer {
  final String wallet;
  final bool battling;
  const OnlinePlayer({required this.wallet, required this.battling});

  factory OnlinePlayer.fromJson(Map<String, dynamic> json) {
    return OnlinePlayer(wallet: json['wallet'] as String, battling: json['battling'] as bool? ?? false);
  }
}

class ChallengeSummary {
  final int id;
  final String challengerWallet;
  final int challengerCreatureTokenId;
  final int challengerSpecies;
  final int challengerRarity;
  final int challengerLevel;
  final String status; // open | completed | cancelled | expired
  final String? challengedWallet;
  final String? opponentWallet;
  final String? winnerWallet;
  final int? rounds;
  final List<String>? log;
  final String? rewardFeed;
  final String wagerWei;
  final bool escrowConfirmed;
  final DateTime createdAt;
  final DateTime expiresAt;

  const ChallengeSummary({
    required this.id,
    required this.challengerWallet,
    required this.challengerCreatureTokenId,
    required this.challengerSpecies,
    required this.challengerRarity,
    required this.challengerLevel,
    required this.status,
    this.challengedWallet,
    this.opponentWallet,
    this.winnerWallet,
    this.rounds,
    this.log,
    this.rewardFeed,
    this.wagerWei = '0',
    this.escrowConfirmed = true,
    required this.createdAt,
    required this.expiresAt,
  });

  factory ChallengeSummary.fromJson(Map<String, dynamic> json) {
    return ChallengeSummary(
      id: json['id'] as int,
      challengerWallet: json['challengerWallet'] as String,
      challengerCreatureTokenId: json['challengerCreatureTokenId'] as int,
      challengerSpecies: json['challengerSpecies'] as int,
      challengerRarity: json['challengerRarity'] as int,
      challengerLevel: json['challengerLevel'] as int,
      status: json['status'] as String,
      challengedWallet: json['challengedWallet'] as String?,
      opponentWallet: json['opponentWallet'] as String?,
      winnerWallet: json['winnerWallet'] as String?,
      rounds: json['rounds'] as int?,
      log: (json['log'] as List<dynamic>?)?.cast<String>(),
      rewardFeed: json['rewardFeed'] as String?,
      wagerWei: json['wagerWei'] as String? ?? '0',
      escrowConfirmed: json['escrowConfirmed'] as bool? ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
    );
  }
}

class AbilityInfo {
  final String key;
  final String name;
  final String description;

  const AbilityInfo({required this.key, required this.name, required this.description});

  factory AbilityInfo.fromJson(Map<String, dynamic> json) {
    return AbilityInfo(
      key: json['key'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
    );
  }
}
