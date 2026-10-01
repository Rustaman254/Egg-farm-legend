part of 'task_bloc.dart';

sealed class TaskEvent extends Equatable {
  const TaskEvent();
  @override
  List<Object?> get props => [];
}

class TasksRequested extends TaskEvent {
  final String wallet;
  const TasksRequested(this.wallet);
  @override
  List<Object?> get props => [wallet];
}

class TaskClaimed extends TaskEvent {
  final String taskId;
  const TaskClaimed(this.taskId);
  @override
  List<Object?> get props => [taskId];
}
