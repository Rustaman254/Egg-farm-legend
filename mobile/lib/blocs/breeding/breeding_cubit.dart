import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/repositories/farm_repository.dart';

class BreedingState extends Equatable {
  final int? parent1;
  final int? parent2;
  final bool isBreeding;
  final String? error;
  final String? lastTxHash;

  const BreedingState({this.parent1, this.parent2, this.isBreeding = false, this.error, this.lastTxHash});

  bool get canBreed => parent1 != null && parent2 != null && parent1 != parent2 && !isBreeding;

  BreedingState copyWith({
    int? parent1,
    bool clearParent1 = false,
    int? parent2,
    bool clearParent2 = false,
    bool? isBreeding,
    String? error,
    bool clearError = false,
    String? lastTxHash,
  }) {
    return BreedingState(
      parent1: clearParent1 ? null : (parent1 ?? this.parent1),
      parent2: clearParent2 ? null : (parent2 ?? this.parent2),
      isBreeding: isBreeding ?? this.isBreeding,
      error: clearError ? null : (error ?? this.error),
      lastTxHash: lastTxHash ?? this.lastTxHash,
    );
  }

  @override
  List<Object?> get props => [parent1, parent2, isBreeding, error, lastTxHash];
}

/// Selection + submission state for the Breeding Lab screen. Kept separate from FarmBloc
/// because parent selection is transient UI state, not farm data.
class BreedingCubit extends Cubit<BreedingState> {
  final FarmRepository repository;
  BreedingCubit(this.repository) : super(const BreedingState());

  void selectParent1(int tokenId) {
    if (state.parent2 == tokenId) return;
    emit(state.copyWith(parent1: tokenId, clearError: true));
  }

  void selectParent2(int tokenId) {
    if (state.parent1 == tokenId) return;
    emit(state.copyWith(parent2: tokenId, clearError: true));
  }

  void clearSelection() {
    emit(const BreedingState());
  }

  Future<void> breed() async {
    if (!state.canBreed) return;
    emit(state.copyWith(isBreeding: true, clearError: true));
    try {
      final txHash = await repository.breedCreatures(state.parent1!, state.parent2!);
      emit(BreedingState(isBreeding: false, lastTxHash: txHash));
    } catch (e) {
      emit(state.copyWith(isBreeding: false, error: e.toString()));
    }
  }
}
