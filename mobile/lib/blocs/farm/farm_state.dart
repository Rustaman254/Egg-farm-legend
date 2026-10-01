part of 'farm_bloc.dart';

sealed class FarmState extends Equatable {
  const FarmState();
  @override
  List<Object?> get props => [];
}

class FarmInitial extends FarmState {
  const FarmInitial();
}

class FarmLoading extends FarmState {
  const FarmLoading();
}

class FarmLoaded extends FarmState {
  final List<Creature> creatures;
  final List<Egg> eggs;
  final String feedBalance;
  final String? pendingActionMessage; // e.g. "Feeding..." shown while a tx is in flight
  final String? actionError;

  const FarmLoaded({
    required this.creatures,
    required this.eggs,
    required this.feedBalance,
    this.pendingActionMessage,
    this.actionError,
  });

  FarmLoaded copyWith({
    List<Creature>? creatures,
    List<Egg>? eggs,
    String? feedBalance,
    String? pendingActionMessage,
    bool clearPending = false,
    String? actionError,
    bool clearError = false,
  }) {
    return FarmLoaded(
      creatures: creatures ?? this.creatures,
      eggs: eggs ?? this.eggs,
      feedBalance: feedBalance ?? this.feedBalance,
      pendingActionMessage: clearPending ? null : (pendingActionMessage ?? this.pendingActionMessage),
      actionError: clearError ? null : (actionError ?? this.actionError),
    );
  }

  @override
  List<Object?> get props => [creatures, eggs, feedBalance, pendingActionMessage, actionError];
}

class FarmError extends FarmState {
  final String message;
  const FarmError(this.message);
  @override
  List<Object?> get props => [message];
}
