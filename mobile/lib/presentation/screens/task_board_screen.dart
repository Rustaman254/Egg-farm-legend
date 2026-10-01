import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/task/task_bloc.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/game_task.dart';
import '../widgets/brand_app_bar.dart';

class TaskBoardScreen extends StatefulWidget {
  final String wallet;
  const TaskBoardScreen({super.key, required this.wallet});

  @override
  State<TaskBoardScreen> createState() => _TaskBoardScreenState();
}

class _TaskBoardScreenState extends State<TaskBoardScreen> {
  @override
  void initState() {
    super.initState();
    context.read<TaskBloc>().add(TasksRequested(widget.wallet));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BrandAppBar(title: 'Daily Tasks', icon: Icons.checklist),
      body: BlocConsumer<TaskBloc, TaskState>(
        listener: (context, state) {
          if (state is TaskLoaded && state.error != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.error!), backgroundColor: AppColors.danger),
            );
          }
        },
        builder: (context, state) {
          if (state is TaskLoading || state is TaskInitial) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }
          if (state is TaskError) {
            return Center(child: Text(state.message));
          }
          final loaded = state as TaskLoaded;
          final claimable = loaded.tasks.where((t) => t.isClaimable).length;

          return RefreshIndicator(
            onRefresh: () async => context.read<TaskBloc>().add(TasksRequested(widget.wallet)),
            child: CustomScrollView(
              slivers: [
                if (claimable > 0)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    sliver: SliverToBoxAdapter(child: _ClaimableBanner(count: claimable)),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.78,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final task = loaded.tasks[index];
                        final isClaiming = loaded.claimingTaskId == task.taskId;
                        return _TaskCard(
                          task: task,
                          isClaiming: isClaiming,
                          onClaim: () => context.read<TaskBloc>().add(TaskClaimed(task.taskId)),
                        );
                      },
                      childCount: loaded.tasks.length,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ClaimableBanner extends StatelessWidget {
  final int count;
  const _ClaimableBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🎁', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Text('$count ready to claim', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }
}

/// A Pokemon-TCG-styled task card: colored border by status, circular icon badge, progress bar,
/// and a footer action -- mirrors the webapp's TaskCard/CreatureCard so tasks read as the same
/// kind of collectible object as the rest of the game.
class _TaskCard extends StatelessWidget {
  final GameTask task;
  final bool isClaiming;
  final VoidCallback onClaim;

  const _TaskCard({required this.task, required this.isClaiming, required this.onClaim});

  @override
  Widget build(BuildContext context) {
    final accent = task.rewardClaimed ? AppColors.secondary : (task.isClaimable ? AppColors.primary : AppColors.border);

    return Container(
      decoration: cardPopDecoration(borderColor: accent, small: true),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [accent.withValues(alpha: 0.35), accent.withValues(alpha: 0.08)]),
              border: Border.all(color: accent, width: 2.5),
            ),
            alignment: Alignment.center,
            child: Text(TaskDisplay.emojiFor(task.taskId), style: const TextStyle(fontSize: 26)),
          ),
          const SizedBox(height: 8),
          Text(
            TaskDisplay.titleFor(task.taskId),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            TaskDisplay.descriptionFor(task.taskId),
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: task.progress,
              minHeight: 6,
              backgroundColor: AppColors.surface2,
              valueColor: AlwaysStoppedAnimation(task.isCompleted ? AppColors.secondary : AppColors.primary),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${task.currentCount}/${task.targetCount} · +${task.rewardFeedWhole.toStringAsFixed(0)} FEED',
            style: const TextStyle(fontSize: 10, color: AppColors.textFaint),
          ),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: _buildActionButton()),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    if (task.rewardClaimed) {
      return const Center(
        child: Text('✓ Claimed', style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold, fontSize: 12)),
      );
    }
    if (!task.isCompleted) {
      return const Center(
        child: Text('⏳ In progress', style: TextStyle(color: AppColors.textFaint, fontSize: 12)),
      );
    }
    return ElevatedButton(
      onPressed: isClaiming ? null : onClaim,
      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8), minimumSize: Size.zero),
      child: isClaiming
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Text('Claim', style: TextStyle(fontSize: 12)),
    );
  }
}
