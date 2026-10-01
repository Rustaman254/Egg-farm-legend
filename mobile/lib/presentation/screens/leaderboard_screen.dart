import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/leaderboard/leaderboard_cubit.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/leaderboard_entry.dart';
import '../widgets/brand_app_bar.dart';

Color _medalColor(int rank) {
  if (rank == 0) return AppColors.gold;
  if (rank == 1) return const Color(0xFFC0C0C0);
  if (rank == 2) return const Color(0xFFCD7F32);
  return AppColors.textFaint;
}

/// Mirrors the webapp's LeaderboardPage: Top Trainers (battle wins) and Top Traders
/// (marketplace earnings), as tabs rather than the webapp's two side-by-side buttons.
class LeaderboardScreen extends StatefulWidget {
  final String wallet;
  const LeaderboardScreen({super.key, required this.wallet});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    context.read<LeaderboardCubit>().load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandAppBar(
        title: 'Leaderboard',
        icon: Icons.emoji_events,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.sports_kabaddi, size: 18), text: 'Top Trainers'),
            Tab(icon: Icon(Icons.emoji_events, size: 18), text: 'Top Traders'),
          ],
        ),
      ),
      body: BlocBuilder<LeaderboardCubit, LeaderboardState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }
          if (state.error != null) {
            return Center(child: Text(state.error!));
          }
          return RefreshIndicator(
            onRefresh: () => context.read<LeaderboardCubit>().load(),
            child: TabBarView(
              controller: _tabController,
              children: [
                _BattlersTab(wallet: widget.wallet, battlers: state.battlers),
                _EarnersTab(wallet: widget.wallet, earners: state.earners),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BattlersTab extends StatelessWidget {
  final String wallet;
  final List<TopBattler> battlers;
  const _BattlersTab({required this.wallet, required this.battlers});

  @override
  Widget build(BuildContext context) {
    if (battlers.isEmpty) {
      return const _EmptyState(message: 'No battles fought yet. Be the first champion in the Battle Arena!');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: battlers.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final b = battlers[index];
        return _LeaderboardRow(
          rank: index,
          address: b.wallet,
          isMe: b.wallet.toLowerCase() == wallet.toLowerCase(),
          primary: '${b.wins} wins',
          secondary: '${b.total} battles fought',
        );
      },
    );
  }
}

class _EarnersTab extends StatelessWidget {
  final String wallet;
  final List<TopEarner> earners;
  const _EarnersTab({required this.wallet, required this.earners});

  @override
  Widget build(BuildContext context) {
    if (earners.isEmpty) {
      return const _EmptyState(message: 'No sales yet. List something on the Marketplace to get on the board!');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: earners.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final e = earners[index];
        final sales = e.sales == 1 ? '1 sale' : '${e.sales} sales';
        return _LeaderboardRow(
          rank: index,
          address: e.wallet,
          isMe: e.wallet.toLowerCase() == wallet.toLowerCase(),
          primary: '${weiToWhole(e.totalWei).toStringAsFixed(2)} ARB',
          secondary: sales,
        );
      },
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final int rank;
  final String address;
  final bool isMe;
  final String primary;
  final String secondary;

  const _LeaderboardRow({
    required this.rank,
    required this.address,
    required this.isMe,
    required this.primary,
    required this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isMe ? AppColors.accent : AppColors.border, width: 2),
      ),
      child: Row(
        children: [
          CircleAvatar(radius: 14, backgroundColor: _medalColor(rank), child: Text('${rank + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(shortAddress(address), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    if (isMe) const Padding(padding: EdgeInsets.only(left: 4), child: Text('(You)', style: TextStyle(fontSize: 11, color: AppColors.accent))),
                  ],
                ),
                Text(secondary, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
          Text(primary, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
      ),
    );
  }
}
