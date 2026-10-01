class WalletEvent {
  final int id;
  final String kind; // balance_up | balance_down | listing_sold | listing_bought
  final String message;
  final String? amountWei;
  final String createdAt;

  const WalletEvent({
    required this.id,
    required this.kind,
    required this.message,
    this.amountWei,
    required this.createdAt,
  });

  factory WalletEvent.fromJson(Map<String, dynamic> json) => WalletEvent(
        id: json['id'] as int,
        kind: json['kind'] as String,
        message: json['message'] as String,
        amountWei: json['amountWei'] as String?,
        createdAt: json['createdAt'] as String,
      );
}

class WagerActivityEntry {
  final int challengeId;
  final String opponentWallet;
  final String wagerWei;
  final bool won;
  final String resolvedAt;

  const WagerActivityEntry({
    required this.challengeId,
    required this.opponentWallet,
    required this.wagerWei,
    required this.won,
    required this.resolvedAt,
  });

  factory WagerActivityEntry.fromJson(Map<String, dynamic> json) => WagerActivityEntry(
        challengeId: json['challengeId'] as int,
        opponentWallet: json['opponentWallet'] as String,
        wagerWei: json['wagerWei'] as String? ?? '0',
        won: json['won'] as bool? ?? false,
        resolvedAt: json['resolvedAt'] as String,
      );
}

class PlatformTxEntry {
  final String source; // wager_rake | quest_funding | feed_shop
  final String nativeAmountWei;
  final String feedAmount;
  final String createdAt;

  const PlatformTxEntry({
    required this.source,
    required this.nativeAmountWei,
    required this.feedAmount,
    required this.createdAt,
  });

  factory PlatformTxEntry.fromJson(Map<String, dynamic> json) => PlatformTxEntry(
        source: json['source'] as String,
        nativeAmountWei: json['nativeAmountWei'] as String? ?? '0',
        feedAmount: json['feedAmount'] as String? ?? '0',
        createdAt: json['createdAt'] as String,
      );
}

class BattleHistoryEntry {
  final int creatureTokenId;
  final int opponentSpecies;
  final int opponentRarity;
  final bool won;
  final String rewardFeed;
  final String createdAt;

  const BattleHistoryEntry({
    required this.creatureTokenId,
    required this.opponentSpecies,
    required this.opponentRarity,
    required this.won,
    required this.rewardFeed,
    required this.createdAt,
  });

  factory BattleHistoryEntry.fromJson(Map<String, dynamic> json) => BattleHistoryEntry(
        creatureTokenId: json['creatureTokenId'] as int,
        opponentSpecies: json['opponentSpecies'] as int,
        opponentRarity: json['opponentRarity'] as int,
        won: json['won'] as bool? ?? false,
        rewardFeed: json['rewardFeed'] as String? ?? '0',
        createdAt: json['createdAt'] as String,
      );
}

class PlayerActivity {
  final List<BattleHistoryEntry> battles;
  final List<WagerActivityEntry> wagers;
  final List<PlatformTxEntry> platformTx;
  final List<WalletEvent> walletEvents;

  const PlayerActivity({
    required this.battles,
    required this.wagers,
    required this.platformTx,
    required this.walletEvents,
  });

  factory PlayerActivity.fromJson(Map<String, dynamic> json) => PlayerActivity(
        battles: (json['battles'] as List<dynamic>? ?? [])
            .map((e) => BattleHistoryEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        wagers: (json['wagers'] as List<dynamic>? ?? [])
            .map((e) => WagerActivityEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        platformTx: (json['platformTx'] as List<dynamic>? ?? [])
            .map((e) => PlatformTxEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        walletEvents: (json['walletEvents'] as List<dynamic>? ?? [])
            .map((e) => WalletEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
