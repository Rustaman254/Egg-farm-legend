import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/models/creature.dart';
import '../../data/models/egg.dart';
import '../../data/repositories/farm_repository.dart';

part 'farm_event.dart';
part 'farm_state.dart';

/// The on-chain write (feed/lay/hatch/purchase) confirms well before the backend's indexer has
/// necessarily caught up and rewritten Postgres, so we optimistically refetch after a short
/// delay rather than blocking the UI on indexer lag.
const _refetchDelay = Duration(seconds: 2);

class FarmBloc extends Bloc<FarmEvent, FarmState> {
  final FarmRepository repository;
  String? _wallet;

  FarmBloc(this.repository) : super(const FarmInitial()) {
    on<FarmRequested>(_onRequested);
    on<FarmCreatureFed>(_onFed);
    on<FarmEggCollected>(_onEggCollected);
    on<FarmEggHatched>(_onEggHatched);
    on<FarmRottenEggDiscarded>(_onRottenEggDiscarded);
    on<FarmCreaturePurchased>(_onPurchased);
  }

  Future<void> _onRequested(FarmRequested event, Emitter<FarmState> emit) async {
    _wallet = event.wallet;
    emit(const FarmLoading());
    await _reload(emit);
  }

  Future<void> _reload(Emitter<FarmState> emit) async {
    if (_wallet == null) return;
    try {
      final snapshot = await repository.getFarm(_wallet!);
      emit(FarmLoaded(creatures: snapshot.creatures, eggs: snapshot.eggs, feedBalance: snapshot.feedBalance));
    } catch (e) {
      emit(FarmError(e.toString()));
    }
  }

  Future<void> _runAction(
    Emitter<FarmState> emit,
    String pendingMessage,
    Future<void> Function() action,
  ) async {
    final current = state;
    if (current is! FarmLoaded) return;

    emit(current.copyWith(pendingActionMessage: pendingMessage, clearError: true));
    try {
      await action();
      await Future.delayed(_refetchDelay);
      await _reload(emit);
    } catch (e) {
      final latest = state;
      if (latest is FarmLoaded) {
        emit(latest.copyWith(clearPending: true, actionError: e.toString()));
      }
    }
  }

  Future<void> _onFed(FarmCreatureFed event, Emitter<FarmState> emit) =>
      _runAction(emit, 'Feeding...', () => repository.feedCreature(event.tokenId));

  Future<void> _onEggCollected(FarmEggCollected event, Emitter<FarmState> emit) =>
      _runAction(emit, 'Collecting egg...', () => repository.layEgg(event.creatureTokenId));

  Future<void> _onEggHatched(FarmEggHatched event, Emitter<FarmState> emit) =>
      _runAction(emit, 'Hatching...', () => repository.hatchEgg(event.eggTokenId));

  Future<void> _onRottenEggDiscarded(FarmRottenEggDiscarded event, Emitter<FarmState> emit) =>
      _runAction(emit, 'Discarding...', () => repository.discardRottenEgg(event.eggTokenId));

  Future<void> _onPurchased(FarmCreaturePurchased event, Emitter<FarmState> emit) => _runAction(
        emit,
        'Purchasing creature...',
        () => repository.purchaseCreature(event.rarityTier, event.priceArb),
      );
}
