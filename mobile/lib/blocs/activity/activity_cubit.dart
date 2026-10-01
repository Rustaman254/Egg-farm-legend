import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/models/activity.dart';
import '../../data/repositories/stats_repository.dart';

abstract class ActivityState extends Equatable {
  const ActivityState();
  @override
  List<Object?> get props => [];
}

class ActivityInitial extends ActivityState {
  const ActivityInitial();
}

class ActivityLoading extends ActivityState {
  const ActivityLoading();
}

class ActivityLoaded extends ActivityState {
  final PlayerActivity activity;
  const ActivityLoaded(this.activity);
  @override
  List<Object?> get props => [activity];
}

class ActivityError extends ActivityState {
  final String message;
  const ActivityError(this.message);
  @override
  List<Object?> get props => [message];
}

class ActivityCubit extends Cubit<ActivityState> {
  final StatsRepository repository;
  ActivityCubit(this.repository) : super(const ActivityInitial());

  Future<void> load(String wallet) async {
    emit(const ActivityLoading());
    try {
      final activity = await repository.getActivity(wallet);
      emit(ActivityLoaded(activity));
    } catch (e) {
      emit(ActivityError(e.toString()));
    }
  }
}
