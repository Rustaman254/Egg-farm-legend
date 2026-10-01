import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/farm/farm_bloc.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/brand_app_bar.dart';
import '../widgets/creature_card.dart';
import 'shop_sheet.dart';

class FarmScreen extends StatefulWidget {
  final String wallet;
  const FarmScreen({super.key, required this.wallet});

  @override
  State<FarmScreen> createState() => _FarmScreenState();
}

class _FarmScreenState extends State<FarmScreen> {
  @override
  void initState() {
    super.initState();
    context.read<FarmBloc>().add(FarmRequested(widget.wallet));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandAppBar(title: 'My Farm', icon: Icons.agriculture),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        onPressed: () => showShopSheet(context, widget.wallet),
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('Buy Creature'),
      ),
      body: BlocConsumer<FarmBloc, FarmState>(
        listener: (context, state) {
          if (state is FarmLoaded && state.actionError != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.actionError!), backgroundColor: AppColors.danger),
            );
          }
        },
        builder: (context, state) {
          if (state is FarmLoading || state is FarmInitial) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }
          if (state is FarmError) {
            return _ErrorView(message: state.message, onRetry: () => context.read<FarmBloc>().add(FarmRequested(widget.wallet)));
          }
          final loaded = state as FarmLoaded;

          return RefreshIndicator(
            onRefresh: () async => context.read<FarmBloc>().add(FarmRequested(widget.wallet)),
            child: Stack(
              children: [
                CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      sliver: SliverToBoxAdapter(child: _BalanceHero(feedBalance: loaded.feedBalance)),
                    ),
                    if (loaded.creatures.isEmpty)
                      SliverFillRemaining(hasScrollBody: false, child: _EmptyFarmView(onBuy: () => showShopSheet(context, widget.wallet)))
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 96),
                        sliver: SliverGrid(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.62,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final creature = loaded.creatures[index];
                              return CreatureCard(
                                creature: creature,
                                onFeed: () => context.read<FarmBloc>().add(FarmCreatureFed(creature.tokenId)),
                                onCollectEgg: creature.canLayEgg
                                    ? () => context.read<FarmBloc>().add(FarmEggCollected(creature.tokenId))
                                    : null,
                              );
                            },
                            childCount: loaded.creatures.length,
                          ),
                        ),
                      ),
                  ],
                ),
                if (loaded.pendingActionMessage != null)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: _PendingBanner(message: loaded.pendingActionMessage!),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Mirrors the FarmPage.tsx hero's FEED-balance panel -- a bold headline number on a
/// brand-yellow-tinted card, the same "your balance" framing the webapp leads with.
class _BalanceHero extends StatelessWidget {
  final String feedBalance;
  const _BalanceHero({required this.feedBalance});

  @override
  Widget build(BuildContext context) {
    final value = BigInt.tryParse(feedBalance) ?? BigInt.zero;
    final whole = (value ~/ BigInt.from(10).pow(18)).toString();

    return Container(
      decoration: cardPopDecoration(borderColor: AppColors.gold, fill: Color.lerp(AppColors.cardSurface, AppColors.gold, 0.12)),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, size: 14, color: AppColors.gold),
              SizedBox(width: 6),
              Text('YOUR BALANCE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.gold, letterSpacing: 0.6)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(whole, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
              const SizedBox(width: 6),
              const Text('FEED', style: TextStyle(fontSize: 16, color: AppColors.textMuted, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          const Text('Earn more by completing tasks and collecting eggs.', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _EmptyFarmView extends StatelessWidget {
  final VoidCallback onBuy;
  const _EmptyFarmView({required this.onBuy});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🐣', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            const Text('Your farm is empty', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Buy your first creature to get started', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: onBuy, child: const Text('Buy Your First Creature')),
          ],
        ),
      ),
    );
  }
}

class _PendingBanner extends StatelessWidget {
  final String message;
  const _PendingBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: cardPopDecoration(borderColor: AppColors.border, fill: AppColors.accent),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
