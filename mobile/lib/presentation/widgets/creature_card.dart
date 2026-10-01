import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/battle/battle_cubit.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/battle_stats.dart' as stats;
import '../../core/theme/app_theme.dart';
import '../../data/models/creature.dart';
import 'ability_badges.dart';
import 'stat_bar.dart';

/// A Pokemon-TCG-styled card mirroring the webapp's CreatureCard: colored border by rarity/
/// selection, HP badge in the corner, a glossy circular art frame, attack-row stats, and a
/// dex-number footer. Used both as the selectable Breeding Lab/Battle tile and (non-selectable)
/// as the standalone Farm grid card.
class CreatureCard extends StatelessWidget {
  final Creature creature;
  final VoidCallback? onFeed;
  final VoidCallback? onCollectEgg;
  final VoidCallback? onTap;
  final bool selectable;
  final bool selected;

  const CreatureCard({
    super.key,
    required this.creature,
    this.onFeed,
    this.onCollectEgg,
    this.onTap,
    this.selectable = false,
    this.selected = false,
  });

  String _formatCooldown(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h';
    return '${d.inMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final rarityColor = AppColors.forRarity(creature.rarity);
    final borderColor = selected ? AppColors.accent : rarityColor;
    final cooldown = creature.eggCooldownRemaining;
    final battleStats = stats.battleStats(creature.species, creature.rarity, creature.careScore);
    final level = stats.levelForCareScore(creature.careScore);
    final catalog = context.select((BattleCubit c) => c.state.abilityCatalog);

    return InkWell(
      onTap: onTap ?? (selectable ? onFeed : null),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: cardPopDecoration(borderColor: borderColor, small: true),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        GameConstants.speciesName(creature.species),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${GameConstants.rarityLabels[creature.rarity]} · Lv$level',
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.textFaint),
                      ),
                      Text(
                        creature.condition,
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: _conditionColor(creature.condition)),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(8)),
                  child: Text('HP ${battleStats.hp}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: RadialGradient(colors: [rarityColor.withValues(alpha: 0.35), rarityColor.withValues(alpha: 0.08)]),
              ),
              alignment: Alignment.center,
              child: Text(GameConstants.speciesEmojiFor(creature.species), style: const TextStyle(fontSize: 38)),
            ),
            const SizedBox(height: 8),
            _dashedDivider(),
            const SizedBox(height: 4),
            _statRow(Icons.bolt, AppColors.primary, 'Attack', '${battleStats.attack}'),
            _statRow(Icons.shield, AppColors.accent, 'Defense', '${battleStats.defense}'),
            _statRow(Icons.repeat, AppColors.textFaint, 'Bred', '${creature.breedCount}/${GameConstants.maxBreedCount}'),
            const SizedBox(height: 6),
            StatBar(label: 'Hunger', value: creature.hunger, icon: Icons.restaurant),
            const SizedBox(height: 4),
            StatBar(label: 'Happiness', value: creature.happiness, icon: Icons.favorite),
            if (creature.abilities.isNotEmpty) ...[
              const SizedBox(height: 6),
              AbilityBadges(abilities: creature.abilities, catalog: catalog),
            ],
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('No. ${creature.species.toString().padLeft(3, '0')}', style: const TextStyle(fontSize: 9, color: AppColors.textFaint)),
                Text('#${creature.tokenId}', style: const TextStyle(fontSize: 9, color: AppColors.textFaint)),
              ],
            ),
            if (!selectable) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _ActionButton(label: creature.hunger >= 100 ? 'Full' : 'Feed', filled: false, onPressed: creature.hunger >= 100 ? null : onFeed)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _ActionButton(
                      label: creature.canLayEgg ? 'Egg' : (cooldown != null ? _formatCooldown(cooldown) : 'Unhappy'),
                      filled: true,
                      onPressed: creature.canLayEgg ? onCollectEgg : null,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statRow(IconData icon, Color color, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
          Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _dashedDivider() => Container(height: 1, color: AppColors.border);
}

class _ActionButton extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback? onPressed;

  const _ActionButton({required this.label, required this.filled, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return ElevatedButton(
      onPressed: enabled
          ? () {
              HapticFeedback.lightImpact();
              onPressed!();
            }
          : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: enabled ? (filled ? AppColors.primary : AppColors.surface2) : AppColors.surface2,
        foregroundColor: enabled ? (filled ? Colors.white : AppColors.textPrimary) : AppColors.textFaint,
        padding: const EdgeInsets.symmetric(vertical: 8),
        minimumSize: Size.zero,
        elevation: 0,
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}

Color _conditionColor(String condition) {
  switch (condition) {
    case 'Neglected':
      return AppColors.danger;
    case 'Poor':
      return AppColors.warn;
    case 'Fair':
      return AppColors.textMuted;
    case 'Good':
      return AppColors.secondary;
    case 'Excellent':
      return AppColors.primary;
    default:
      return AppColors.textMuted;
  }
}
