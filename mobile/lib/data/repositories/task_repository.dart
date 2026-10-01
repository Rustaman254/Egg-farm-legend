import '../../core/network/api_client.dart';
import '../models/game_task.dart';

class TaskRepository {
  final ApiClient api;
  TaskRepository({required this.api});

  Future<List<GameTask>> listTasks(String wallet) async {
    final json = await api.listTasks(wallet);
    return json.map((e) => GameTask.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<String> claimTask(String wallet, String taskId) => api.claimTask(wallet, taskId);

  Future<void> recordLogin(String wallet) => api.recordLogin(wallet);
}
