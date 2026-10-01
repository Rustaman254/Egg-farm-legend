import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/breeding/breeding_cubit.dart';
import '../../blocs/farm/farm_bloc.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/creature.dart';
import '../widgets/brand_app_bar.dart';
import '../widgets/creature_card.dart';

class BreedingLabScreen extends StatelessWidget {
  final String wallet;
  const BreedingLabScreen({super.key, required this.wallet});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BrandAppBar(title: 'Breeding Lab', icon: Icons.science),
      body: BlocBuilder<FarmBloc, FarmState>(
        builder: (context, farmState) {
          final creatures = farmState is FarmLoaded
              ? farmState.creatures.where((c) => c.canBreed && !c.isDead).toList()
              : <Creature>[];

          if (creatures.length < 2) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'You need at least 2 breedable creatures (breed count < 7) to use the Breeding Lab.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
            );
          }

          return BlocConsumer<BreedingCubit, BreedingState>(
            listener: (context, state) {
              if (state.lastTxHash != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Breeding started! Check Inventory for the new egg.'), backgroundColor: AppColors.secondary),
                );
                context.read<BreedingCubit>().clearSelection();
              }
              if (state.error != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(state.error!), backgroundColor: AppColors.danger),
                );
              }
            },
            builder: (context, breedState) {
              return Column(
                children: [
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.62,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: creatures.length,
                      itemBuilder: (context, index) {
                        final creature = creatures[index];
                        final isParent1 = breedState.parent1 == creature.tokenId;
                        final isParent2 = breedState.parent2 == creature.tokenId;
                        return _SelectableCreature(
                          creature: creature,
                          slot: isParent1 ? 1 : (isParent2 ? 2 : null),
                          onTap: () {
                            final cubit = context.read<BreedingCubit>();
                            if (isParent1 || isParent2) {
                              cubit.clearSelection();
                            } else if (breedState.parent1 == null) {
                              cubit.selectParent1(creature.tokenId);
                            } else if (breedState.parent2 == null) {
                              cubit.selectParent2(creature.tokenId);
                            }
                          },
                        );
                      },
                    ),
                  ),
                  _BreedingPanel(
                    creatures: creatures,
                    state: breedState,
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _SelectableCreature extends StatelessWidget {
  final Creature creature;
  final int? slot; // 1, 2, or null
  final VoidCallback onTap;

  const _SelectableCreature({required this.creature, required this.slot, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CreatureCard(creature: creature, selectable: true, selected: slot != null, onTap: onTap),
        if (slot != null)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: slot == 1 ? AppColors.primary : AppColors.accent,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
              ),
              alignment: Alignment.center,
              child: Text('$slot', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }
}

class _BreedingPanel extends StatelessWidget {
  final List<Creature> creatures;
  final BreedingState state;

  const _BreedingPanel({required this.creatures, required this.state});

  @override
  Widget build(BuildContext context) {
    Creature? find(int? id) => id == null ? null : creatures.firstWhere((c) => c.tokenId == id);
    final p1 = find(state.parent1);
    final p2 = find(state.parent2);

    String prediction = 'Select two parents';
    bool interbreeding = false;
    if (p1 != null && p2 != null) {
      final avg = ((p1.rarity + p2.rarity) / 2).floor();
      final low = (avg - 1).clamp(1, GameConstants.maxRarity);
      final high = (avg + 2).clamp(1, GameConstants.maxRarity);
      prediction = 'Predicted offspring rarity: $low - $high stars';
      interbreeding = p1.species != p2.species;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        border: Border(top: BorderSide(color: AppColors.border, width: 2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (p1 != null && p2 != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${GameConstants.speciesName(p1.species)} × ${GameConstants.speciesName(p2.species)}',
                style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
              ),
            ),
          Text(prediction, style: const TextStyle(fontWeight: FontWeight.bold)),
          if (p1 != null && p2 != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                interbreeding ? '✨ Interbreeding: ~60% chance of a brand-new species' : 'Same species: ~20% chance of a mutation, otherwise breeds true',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: interbreeding ? AppColors.primary : AppColors.textFaint),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 4),
          const Text(
            'Cost: 50+ FEED (scales with breed count) + 0.01 ARB · Incubation 24-72h',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: state.canBreed ? () => context.read<BreedingCubit>().breed() : null,
              child: state.isBreeding
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Breed'),
            ),
          ),
        ],
      ),
    );
  }
}
