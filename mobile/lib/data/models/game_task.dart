/// Named `GameTask` (not `Task`) to avoid clashing with dart:async's Task-adjacent APIs.
class GameTask {
  final String taskId;
  final int currentCount;
  final int targetCount;
  final DateTime? completedAt;
  final bool rewardClaimed;
  final String rewardFeed; // 18-decimal string

  const GameTask({
    required this.taskId,
    required this.currentCount,
    required this.targetCount,
    this.completedAt,
    required this.rewardClaimed,
    required this.rewardFeed,
  });

  bool get isCompleted => completedAt != null;
  bool get isClaimable => isCompleted && !rewardClaimed;
  double get progress => targetCount == 0 ? 0 : (currentCount / targetCount).clamp(0, 1);

  double get rewardFeedWhole {
    final raw = BigInt.tryParse(rewardFeed) ?? BigInt.zero;
    return raw / BigInt.from(10).pow(18);
  }

  factory GameTask.fromJson(Map<String, dynamic> json) {
    return GameTask(
      taskId: json['taskId'] as String,
      currentCount: json['currentCount'] as int,
      targetCount: json['targetCount'] as int,
      completedAt: json['completedAt'] != null ? DateTime.parse(json['completedAt'] as String) : null,
      rewardClaimed: json['rewardClaimed'] as bool,
      rewardFeed: json['rewardFeed'] as String,
    );
  }
}

/// Static display metadata for known task IDs (title/description live in the backend catalog
/// too, but the app ships sensible fallbacks so the board renders even before first sync).
class TaskDisplay {
  static const Map<String, ({String title, String description, String emoji})> _catalog = {
    'feed_3_times': (title: 'Feed 3 Times', description: 'Feed any of your creatures 3 times today', emoji: '🌾'),
    'collect_1_egg': (title: 'Collect 1 Egg', description: 'Collect at least 1 egg from your farm', emoji: '🥚'),
    'daily_login': (title: 'Daily Login', description: 'Open the app today', emoji: '📅'),
    'list_1_item': (title: 'List an Item', description: 'List an egg or creature on the marketplace', emoji: '🏷️'),
    'play_minigame': (title: 'Play a Mini-Game', description: 'Complete one round of a mini-game', emoji: '🎮'),
  };

  static String titleFor(String id) => _catalog[id]?.title ?? id;
  static String descriptionFor(String id) => _catalog[id]?.description ?? '';
  static String emojiFor(String id) => _catalog[id]?.emoji ?? '✅';
}
