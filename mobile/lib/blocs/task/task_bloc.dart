import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/models/game_task.dart';
import '../../data/repositories/task_repository.dart';

part 'task_event.dart';
part 'task_state.dart';

class TaskBloc extends Bloc<TaskEvent, TaskState> {
  final TaskRepository repository;
  String? _wallet;

  TaskBloc(this.repository) : super(const TaskInitial()) {
    on<TasksRequested>(_onRequested);
    on<TaskClaimed>(_onClaimed);
  }

  Future<void> _onRequested(TasksRequested event, Emitter<TaskState> emit) async {
    _wallet = event.wallet;
    emit(const TaskLoading());
    await _reload(emit);
  }

  Future<void> _reload(Emitter<TaskState> emit) async {
    if (_wallet == null) return;
    try {
      final tasks = await repository.listTasks(_wallet!);
      emit(TaskLoaded(tasks));
    } catch (e) {
      emit(TaskError(e.toString()));
    }
  }

  Future<void> _onClaimed(TaskClaimed event, Emitter<TaskState> emit) async {
    final current = state;
    if (current is! TaskLoaded || _wallet == null) return;
    emit(current.copyWith(claimingTaskId: event.taskId));
    try {
      await repository.claimTask(_wallet!, event.taskId);
      await _reload(emit);
    } catch (e) {
      emit(current.copyWith(claimingTaskId: null, error: e.toString()));
    }
  }
}
