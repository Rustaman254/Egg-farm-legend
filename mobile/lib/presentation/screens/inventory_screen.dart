import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/farm/farm_bloc.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/brand_app_bar.dart';
import '../widgets/egg_tile.dart';
import 'list_item_sheet.dart';

class InventoryScreen extends StatelessWidget {
  final String wallet;
  const InventoryScreen({super.key, required this.wallet});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BrandAppBar(title: 'Inventory', icon: Icons.inventory_2),
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
            return Center(child: Text(state.message));
          }
          final loaded = state as FarmLoaded;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SectionHeader('🥚 Unhatched Eggs (${loaded.eggs.length})'),
              if (loaded.eggs.isEmpty)
                const _EmptyRow(text: 'No eggs yet — feed your creatures and collect one!')
              else
                ...loaded.eggs.map(
                  (egg) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: EggTile(
                      egg: egg,
                      onHatch: () => context.read<FarmBloc>().add(FarmEggHatched(egg.tokenId)),
                      onDiscard: egg.isRotten ? () => _confirmDiscard(context, egg.tokenId) : null,
                      onList: () => showListItemSheet(context, isEgg: true, tokenId: egg.tokenId),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              _SectionHeader('🐾 Creatures (${loaded.creatures.length})'),
              if (loaded.creatures.isEmpty)
                const _EmptyRow(text: 'No creatures yet — visit the Farm tab to buy one')
              else
                ...loaded.creatures.map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      decoration: cardPopDecoration(borderColor: AppColors.forRarity(c.rarity), small: true),
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.forRarity(c.rarity).withValues(alpha: 0.18),
                              border: Border.all(color: AppColors.forRarity(c.rarity), width: 2),
                            ),
                            alignment: Alignment.center,
                            child: Text(GameConstants.speciesEmojiFor(c.species), style: const TextStyle(fontSize: 20)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${GameConstants.speciesName(c.species)} #${c.tokenId}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  GameConstants.rarityLabels[c.rarity],
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.forRarity(c.rarity)),
                                ),
                                Text(
                                  'Bred ${c.breedCount}/${GameConstants.maxBreedCount} · Hunger ${c.hunger}% · Happy ${c.happiness}%',
                                  style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => showListItemSheet(context, isEgg: false, tokenId: c.tokenId),
                            child: const Text('List', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDiscard(BuildContext context, int tokenId) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard rotten egg?'),
        content: const Text('This egg can never hatch. This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              context.read<FarmBloc>().add(FarmRottenEggDiscarded(tokenId));
            },
            child: const Text('Discard', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.primary, letterSpacing: 0.4),
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  final String text;
  const _EmptyRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(text, style: const TextStyle(color: AppColors.textFaint, fontSize: 12)),
    );
  }
}
