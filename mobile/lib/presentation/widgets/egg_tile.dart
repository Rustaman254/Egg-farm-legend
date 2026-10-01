import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/egg.dart';

/// Mirrors the webapp's EggCard: card-pop-sm border colored by rarity (or rotten-brown), a
/// circular art frame, status line, and a right-aligned action (Hatch/List/Discard). The
/// webapp's Tend/Speed-Up care mechanics aren't wired up in the mobile data layer yet (see
/// FarmRepository), so this stays a presentation-only subset of EggCard.
class EggTile extends StatelessWidget {
  final Egg egg;
  final VoidCallback? onHatch;
  final VoidCallback? onDiscard;
  final VoidCallback? onList;

  const EggTile({super.key, required this.egg, this.onHatch, this.onDiscard, this.onList});

  @override
  Widget build(BuildContext context) {
    final rarityColor = AppColors.forRarity(egg.rarity);
    final borderColor = egg.isRotten ? AppColors.rotten : rarityColor;
    final remaining = egg.timeUntilHatch;

    return Container(
      decoration: cardPopDecoration(borderColor: borderColor, small: true),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: egg.isRotten ? AppColors.surface2 : rarityColor.withValues(alpha: 0.18),
              border: Border.all(color: borderColor, width: 2.5),
            ),
            alignment: Alignment.center,
            child: Text(egg.isRotten ? '💀' : GameConstants.speciesEmojiFor(egg.species), style: const TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  egg.isRotten ? 'Rotten Egg' : "${GameConstants.speciesName(egg.species)}'s Egg",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (!egg.isRotten)
                  Text(
                    '${GameConstants.rarityLabels[egg.rarity]}${egg.isBred ? ' · bred' : ''}',
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.textFaint),
                  ),
                if (!egg.isRotten)
                  Text(
                    egg.isHatchable ? 'Ready to hatch!' : 'Hatches in ${_formatDuration(remaining)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: egg.isHatchable ? AppColors.secondary : AppColors.textMuted,
                      fontWeight: egg.isHatchable ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
              ],
            ),
          ),
          if (egg.isRotten)
            TextButton(onPressed: onDiscard, child: const Text('Discard', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)))
          else if (egg.isHatchable)
            ElevatedButton(onPressed: onHatch, child: const Text('Hatch'))
          else
            TextButton(onPressed: onList, child: const Text('List', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m';
  }
}
