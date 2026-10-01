import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/models/battle.dart';
import '../../data/repositories/battle_repository.dart';

class BattleState extends Equatable {
  final List<OnlinePlayer> online;
  final List<ChallengeSummary> openChallenges;
  final List<ChallengeSummary> myChallenges;
  final List<ChallengeSummary> incomingChallenges;
  final List<BattleHistoryEntry> history;
  final Map<String, AbilityInfo> abilityCatalog;
  final bool isFighting;
  final String? error;
  final BattleResult? lastResult;
  final int? dismissedIncomingId;

  const BattleState({
    this.online = const [],
    this.openChallenges = const [],
    this.myChallenges = const [],
    this.incomingChallenges = const [],
    this.history = const [],
    this.abilityCatalog = const {},
    this.isFighting = false,
    this.error,
    this.lastResult,
    this.dismissedIncomingId,
  });

  /// The incoming challenge to show as a banner, if any (skips one just dismissed locally).
  ChallengeSummary? get bannerChallenge {
    for (final c in incomingChallenges) {
      if (c.id != dismissedIncomingId) return c;
    }
    return null;
  }

  BattleState copyWith({
    List<OnlinePlayer>? online,
    List<ChallengeSummary>? openChallenges,
    List<ChallengeSummary>? myChallenges,
    List<ChallengeSummary>? incomingChallenges,
    List<BattleHistoryEntry>? history,
    Map<String, AbilityInfo>? abilityCatalog,
    bool? isFighting,
    String? error,
    bool clearError = false,
    BattleResult? lastResult,
    bool clearLastResult = false,
    int? dismissedIncomingId,
  }) {
    return BattleState(
      online: online ?? this.online,
      openChallenges: openChallenges ?? this.openChallenges,
      myChallenges: myChallenges ?? this.myChallenges,
      incomingChallenges: incomingChallenges ?? this.incomingChallenges,
      history: history ?? this.history,
      abilityCatalog: abilityCatalog ?? this.abilityCatalog,
      isFighting: isFighting ?? this.isFighting,
      error: clearError ? null : (error ?? this.error),
      lastResult: clearLastResult ? null : (lastResult ?? this.lastResult),
      dismissedIncomingId: dismissedIncomingId ?? this.dismissedIncomingId,
    );
  }

  @override
  List<Object?> get props => [
        online,
        openChallenges,
        myChallenges,
        incomingChallenges,
        history,
        abilityCatalog,
        isFighting,
        error,
        lastResult,
        dismissedIncomingId,
      ];
}

/// Drives the Battle Arena screen: presence heartbeat + polling for online players, the open
/// board, this wallet's own challenges (to notice one got accepted), and direct challenges
/// addressed to this wallet -- the same polling-only fallback the webapp uses when its websocket
/// push can't connect, since the mobile app has no websocket client (yet).
class BattleCubit extends Cubit<BattleState> {
  final BattleRepository repository;
  final String wallet;
  Timer? _heartbeatTimer;
  Timer? _onlineTimer;
  Timer? _openTimer;
  Timer? _mineTimer;
  Timer? _incomingTimer;
  final Set<int> _seenResolvedIds = {};

  BattleCubit({required this.repository, required this.wallet}) : super(const BattleState()) {
    _start();
  }

  void _start() {
    _tickHeartbeat();
    _tickOnline();
    _tickOpen();
    _tickMine();
    _tickIncoming();
    loadHistory();
    _loadAbilityCatalog();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) => _tickHeartbeat());
    _onlineTimer = Timer.periodic(const Duration(seconds: 8), (_) => _tickOnline());
    _openTimer = Timer.periodic(const Duration(seconds: 5), (_) => _tickOpen());
    _mineTimer = Timer.periodic(const Duration(seconds: 5), (_) => _tickMine());
    _incomingTimer = Timer.periodic(const Duration(seconds: 10), (_) => _tickIncoming());
  }

  void _tickHeartbeat() => repository.heartbeat(wallet).catchError((_) {});

  Future<void> _tickOnline() async {
    try {
      final online = await repository.onlinePlayers();
      if (!isClosed) emit(state.copyWith(online: online));
    } catch (_) {}
  }

  Future<void> _tickOpen() async {
    try {
      final open = await repository.openChallenges();
      if (!isClosed) emit(state.copyWith(openChallenges: open));
    } catch (_) {}
  }

  Future<void> _tickMine() async {
    try {
      final mine = await repository.myChallenges(wallet);
      if (isClosed) return;
      // Notice (once) a challenge this wallet posted getting accepted+resolved, same as the
      // webapp's poll-diff -- surfaces it as lastResult so the UI can pop the duel dialog.
      for (final c in mine) {
        if (c.status == 'completed' && c.opponentWallet != null && !_seenResolvedIds.contains(c.id) && (c.log?.isNotEmpty ?? false)) {
          _seenResolvedIds.add(c.id);
          final youWon = c.winnerWallet?.toLowerCase() == wallet.toLowerCase();
          emit(state.copyWith(
            myChallenges: mine,
            lastResult: BattleResult(
              won: youWon,
              playerSpecies: c.challengerSpecies,
              playerLevel: c.challengerLevel,
              playerHp: 0,
              playerMaxHp: 1,
              opponentSpecies: c.challengerSpecies,
              opponentRarity: c.challengerRarity,
              opponentLevel: c.challengerLevel,
              opponentHp: 0,
              opponentMaxHp: 1,
              rounds: c.rounds ?? 0,
              log: c.log ?? const [],
              rewardFeed: c.rewardFeed ?? '0',
              xpAwarded: 0,
              wagerWei: c.wagerWei != '0' ? c.wagerWei : null,
              wagerWon: youWon,
            ),
          ));
          return;
        }
      }
      emit(state.copyWith(myChallenges: mine));
    } catch (_) {}
  }

  Future<void> _tickIncoming() async {
    try {
      final incoming = await repository.incomingChallenges(wallet);
      if (!isClosed) emit(state.copyWith(incomingChallenges: incoming));
    } catch (_) {}
  }

  Future<void> _loadAbilityCatalog() async {
    try {
      final list = await repository.abilityCatalog();
      if (!isClosed) emit(state.copyWith(abilityCatalog: {for (final a in list) a.key: a}));
    } catch (_) {}
  }

  Future<void> loadHistory() async {
    try {
      final history = await repository.history(wallet);
      if (!isClosed) emit(state.copyWith(history: history));
    } catch (_) {}
  }

  Future<void> fightWild(int creatureTokenId) async {
    emit(state.copyWith(isFighting: true, clearError: true));
    try {
      final result = await repository.fight(wallet, creatureTokenId);
      if (isClosed) return;
      emit(state.copyWith(isFighting: false, lastResult: result));
      loadHistory();
    } catch (e) {
      if (!isClosed) emit(state.copyWith(isFighting: false, error: e.toString()));
    }
  }

  // Wagers aren't wired up on mobile yet (the webapp's version stakes an on-chain escrow --
  // see contracts/src/BattleEscrow.sol -- that this repository doesn't call into yet), so this
  // always posts unwagered challenges for now.
  Future<void> postChallenge(int creatureTokenId, {String? challengedWallet}) async {
    emit(state.copyWith(clearError: true));
    try {
      await repository.createChallenge(wallet, creatureTokenId, challengedWallet: challengedWallet);
      await _tickOpen();
      await _tickMine();
    } catch (e) {
      if (!isClosed) emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> accept(int challengeId, int creatureTokenId) async {
    emit(state.copyWith(isFighting: true, clearError: true));
    try {
      final result = await repository.acceptChallenge(wallet, challengeId, creatureTokenId);
      if (isClosed) return;
      emit(state.copyWith(isFighting: false, lastResult: result));
      await _tickOpen();
      await _tickIncoming();
      loadHistory();
    } catch (e) {
      if (!isClosed) emit(state.copyWith(isFighting: false, error: e.toString()));
    }
  }

  Future<void> cancel(int challengeId) async {
    try {
      await repository.cancelChallenge(wallet, challengeId);
      await _tickOpen();
      await _tickMine();
    } catch (e) {
      if (!isClosed) emit(state.copyWith(error: e.toString()));
    }
  }

  void dismissIncoming(int challengeId) => emit(state.copyWith(dismissedIncomingId: challengeId));

  void clearResult() => emit(state.copyWith(clearLastResult: true));

  @override
  Future<void> close() {
    _heartbeatTimer?.cancel();
    _onlineTimer?.cancel();
    _openTimer?.cancel();
    _mineTimer?.cancel();
    _incomingTimer?.cancel();
    return super.close();
  }
}
