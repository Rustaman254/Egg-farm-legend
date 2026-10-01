import '../../core/network/api_client.dart';
import '../models/battle.dart';

/// Wraps the Battle Arena REST surface: PvE fights, presence, and the open+direct challenge
/// board with optional $FEED wagers. Purely backend-authoritative (no on-chain calls) -- a duel
/// is resolved and settled server-side, same as the webapp.
class BattleRepository {
  final ApiClient api;
  BattleRepository({required this.api});

  Future<BattleResult> fight(String wallet, int creatureTokenId) async {
    return BattleResult.fromJson(await api.fightBattle(wallet, creatureTokenId));
  }

  Future<List<BattleHistoryEntry>> history(String wallet) async {
    final list = await api.listBattles(wallet);
    return list.map((e) => BattleHistoryEntry.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> heartbeat(String wallet) => api.arenaHeartbeat(wallet);

  Future<List<OnlinePlayer>> onlinePlayers() async {
    final list = await api.onlinePlayers();
    return list.map((e) => OnlinePlayer.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<ChallengeSummary>> openChallenges() async {
    final list = await api.openChallenges();
    return list.map((e) => ChallengeSummary.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<ChallengeSummary>> myChallenges(String wallet) async {
    final list = await api.myChallenges(wallet);
    return list.map((e) => ChallengeSummary.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<ChallengeSummary>> incomingChallenges(String wallet) async {
    final list = await api.incomingChallenges(wallet);
    return list.map((e) => ChallengeSummary.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ChallengeSummary> createChallenge(
    String wallet,
    int creatureTokenId, {
    String? challengedWallet,
    String wagerWei = '0',
  }) async {
    return ChallengeSummary.fromJson(
      await api.createChallenge(wallet, creatureTokenId, challengedWallet: challengedWallet, wagerWei: wagerWei),
    );
  }

  Future<BattleResult> acceptChallenge(String wallet, int challengeId, int creatureTokenId) async {
    return BattleResult.fromJson(await api.acceptChallenge(wallet, challengeId, creatureTokenId));
  }

  Future<void> cancelChallenge(String wallet, int challengeId) => api.cancelChallenge(wallet, challengeId);

  Future<List<AbilityInfo>> abilityCatalog() async {
    final list = await api.abilityCatalog();
    return list.map((e) => AbilityInfo.fromJson(e as Map<String, dynamic>)).toList();
  }
}
