import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/activity/activity_cubit.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/activity.dart';
import '../widgets/brand_app_bar.dart';

const _platformTxLabels = {
  'wager_rake': 'Platform fee (wager)',
  'quest_funding': 'Funded a quest',
  'feed_shop': 'Bought FEED',
};

/// Mirrors the webapp's ActivityPage: everything that's moved FEED or ETH/ARB on this wallet --
/// live balance changes and marketplace trades, wagered duels, purchases/payments, and recent
/// battle results.
class ActivityScreen extends StatefulWidget {
  final String wallet;
  const ActivityScreen({super.key, required this.wallet});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  @override
  void initState() {
    super.initState();
    context.read<ActivityCubit>().load(widget.wallet);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BrandAppBar(title: 'Activity', icon: Icons.history),
      body: BlocBuilder<ActivityCubit, ActivityState>(
        builder: (context, state) {
          if (state is ActivityLoading || state is ActivityInitial) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }
          if (state is ActivityError) {
            return Center(child: Text(state.message));
          }
          final activity = (state as ActivityLoaded).activity;

          return RefreshIndicator(
            onRefresh: () => context.read<ActivityCubit>().load(widget.wallet),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _Section(
                  title: 'Wallet Activity',
                  icon: Icons.bolt,
                  emptyMessage: "Nothing's happened to your wallet yet -- this fills in live as you play.",
                  children: activity.walletEvents.map((e) => _WalletEventRow(event: e)).toList(),
                ),
                const SizedBox(height: 20),
                _Section(
                  title: 'Wagered Duels',
                  icon: Icons.account_balance_wallet,
                  emptyMessage: 'No wagered duels yet.',
                  children: activity.wagers.map((w) => _WagerRow(wager: w)).toList(),
                ),
                const SizedBox(height: 20),
                _Section(
                  title: 'Payments',
                  icon: Icons.paid,
                  emptyMessage: 'No Feed Shop purchases or quest funding payments yet.',
                  children: activity.platformTx.map((tx) => _PlatformTxRow(tx: tx)).toList(),
                ),
                const SizedBox(height: 20),
                _Section(
                  title: 'Recent Battles',
                  icon: Icons.sports_kabaddi,
                  emptyMessage: 'No battles yet -- head to the Battle Arena.',
                  children: activity.battles.map((b) => _BattleRow(battle: b)).toList(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final String emptyMessage;
  final List<Widget> children;

  const _Section({required this.title, required this.icon, required this.emptyMessage, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: AppColors.textFaint),
            const SizedBox(width: 6),
            Text(
              title.toUpperCase(),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textFaint, letterSpacing: 0.5),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (children.isEmpty)
          Text(emptyMessage, style: const TextStyle(fontSize: 12, color: AppColors.textFaint))
        else
          ...children,
      ],
    );
  }
}

class _RowShell extends StatelessWidget {
  final Widget leading;
  final Widget middle;
  final Widget trailing;
  final String timestamp;

  const _RowShell({required this.leading, required this.middle, required this.trailing, required this.timestamp});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 8),
          Expanded(child: middle),
          trailing,
          const SizedBox(width: 8),
          Text(timestamp, style: const TextStyle(fontSize: 10, color: AppColors.textFaint)),
        ],
      ),
    );
  }
}

class _WalletEventRow extends StatelessWidget {
  final WalletEvent event;
  const _WalletEventRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final isDown = event.kind == 'balance_down';
    return _RowShell(
      leading: Icon(isDown ? Icons.arrow_downward : Icons.arrow_upward, size: 14, color: isDown ? AppColors.danger : AppColors.secondary),
      middle: Text(event.message, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
      trailing: const SizedBox.shrink(),
      timestamp: timeAgo(event.createdAt),
    );
  }
}

class _WagerRow extends StatelessWidget {
  final WagerActivityEntry wager;
  const _WagerRow({required this.wager});

  @override
  Widget build(BuildContext context) {
    final color = wager.won ? AppColors.secondary : AppColors.danger;
    return _RowShell(
      leading: Icon(wager.won ? Icons.arrow_drop_up : Icons.arrow_drop_down, size: 18, color: color),
      middle: Text('vs ${shortAddress(wager.opponentWallet)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      trailing: Text(
        '${wager.won ? '+' : '-'}${weiToWhole(wager.wagerWei)} ETH',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
      timestamp: timeAgo(wager.resolvedAt),
    );
  }
}

class _PlatformTxRow extends StatelessWidget {
  final PlatformTxEntry tx;
  const _PlatformTxRow({required this.tx});

  @override
  Widget build(BuildContext context) {
    final label = _platformTxLabels[tx.source] ?? tx.source;
    final feedWhole = weiToWhole(tx.feedAmount);
    final nativeWhole = weiToWhole(tx.nativeAmountWei);
    final parts = <String>[
      if (nativeWhole > 0) '$nativeWhole ETH',
      if (feedWhole > 0) '+${feedWhole.toStringAsFixed(0)} FEED',
    ];
    return _RowShell(
      leading: const Icon(Icons.monetization_on, size: 14, color: AppColors.textFaint),
      middle: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      trailing: Text(parts.join(' · '), style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
      timestamp: timeAgo(tx.createdAt),
    );
  }
}

class _BattleRow extends StatelessWidget {
  final BattleHistoryEntry battle;
  const _BattleRow({required this.battle});

  @override
  Widget build(BuildContext context) {
    final color = battle.won ? AppColors.secondary : AppColors.danger;
    return _RowShell(
      leading: Text(GameConstants.speciesEmojiFor(battle.opponentSpecies), style: const TextStyle(fontSize: 16)),
      middle: Text('vs ${GameConstants.speciesName(battle.opponentSpecies)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      trailing: Text(battle.won ? 'Won' : 'Lost', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
      timestamp: timeAgo(battle.createdAt),
    );
  }
}
