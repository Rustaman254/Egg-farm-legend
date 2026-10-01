import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/battle.dart';

/// Small pill row for a creature's abilities -- mirrors the webapp's AbilityBadges (surface-2
/// pill, border, brand-yellow sparkle icon). Shown on the stat card (Inventory/Farm) and the
/// Battle Arena's creature picker + duel result. `catalog` resolves keys to display
/// name/description; pass an empty map while it's still loading (falls back to the raw key).
class AbilityBadges extends StatelessWidget {
  final List<String> abilities;
  final Map<String, AbilityInfo> catalog;

  const AbilityBadges({super.key, required this.abilities, this.catalog = const {}});

  @override
  Widget build(BuildContext context) {
    if (abilities.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: abilities.map((key) {
        final info = catalog[key];
        return Tooltip(
          message: info?.description ?? '',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome, size: 9, color: AppColors.gold),
                const SizedBox(width: 3),
                Text(
                  info?.name ?? key,
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
