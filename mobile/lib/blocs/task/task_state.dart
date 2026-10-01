part of 'task_bloc.dart';

sealed class TaskState extends Equatable {
  const TaskState();
  @override
  List<Object?> get props => [];
}

class TaskInitial extends TaskState {
  const TaskInitial();
}

class TaskLoading extends TaskState {
  const TaskLoading();
}

class TaskLoaded extends TaskState {
  final List<GameTask> tasks;
  final String? claimingTaskId;
  final String? error;

  const TaskLoaded(this.tasks, {this.claimingTaskId, this.error});

  TaskLoaded copyWith({List<GameTask>? tasks, String? claimingTaskId, String? error}) {
    return TaskLoaded(tasks ?? this.tasks, claimingTaskId: claimingTaskId, error: error);
  }

  @override
  List<Object?> get props => [tasks, claimingTaskId, error];
}

class TaskError extends TaskState {
  final String message;
  const TaskError(this.message);
  @override
  List<Object?> get props => [message];
}
