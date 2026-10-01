import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/models/leaderboard_entry.dart';
import '../../data/repositories/stats_repository.dart';

class LeaderboardState extends Equatable {
  final List<TopBattler> battlers;
  final List<TopEarner> earners;
  final bool isLoading;
  final String? error;

  const LeaderboardState({
    this.battlers = const [],
    this.earners = const [],
    this.isLoading = false,
    this.error,
  });

  @override
  List<Object?> get props => [battlers, earners, isLoading, error];
}

/// Both boards are fetched together on load since the Leaderboard screen shows them as tabs
/// the player can flip between instantly, rather than lazily fetching per-tab.
class LeaderboardCubit extends Cubit<LeaderboardState> {
  final StatsRepository repository;
  LeaderboardCubit(this.repository) : super(const LeaderboardState(isLoading: true));

  Future<void> load() async {
    emit(const LeaderboardState(isLoading: true));
    try {
      final battlers = await repository.topBattlers();
      final earners = await repository.topEarners();
      emit(LeaderboardState(battlers: battlers, earners: earners));
    } catch (e) {
      emit(LeaderboardState(error: e.toString()));
    }
  }
}
