import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/farm/farm_bloc.dart';
import '../../core/theme/app_theme.dart';

const _tiers = [
  (tier: 1, label: 'Common', priceArb: 0.02, emoji: '🐔'),
  (tier: 2, label: 'Uncommon', priceArb: 0.08, emoji: '🦚'),
  (tier: 3, label: 'Rare', priceArb: 0.25, emoji: '🔥🐦'),
];

void showShopSheet(BuildContext context, String wallet) {
  final farmBloc = context.read<FarmBloc>();
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetContext) => BlocProvider.value(
      value: farmBloc,
      child: const _ShopSheetContent(),
    ),
  );
}

class _ShopSheetContent extends StatelessWidget {
  const _ShopSheetContent();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Buy a Creature', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text('Higher tiers cost more but start with better odds', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 16),
          for (final tier in _tiers) ...[
            _TierTile(
              tier: tier.tier,
              emoji: tier.emoji,
              label: tier.label,
              priceArb: tier.priceArb,
              onBuy: () {
                context.read<FarmBloc>().add(FarmCreaturePurchased(tier.tier, tier.priceArb));
                Navigator.of(context).pop();
              },
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _TierTile extends StatelessWidget {
  final int tier;
  final String emoji;
  final String label;
  final double priceArb;
  final VoidCallback onBuy;

  const _TierTile({required this.tier, required this.emoji, required this.label, required this.priceArb, required this.onBuy});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forRarity(tier);
    return Container(
      decoration: cardPopDecoration(borderColor: color, small: true),
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.18),
              border: Border.all(color: color, width: 2),
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                Text('$priceArb ARB', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
          ),
          ElevatedButton(onPressed: onBuy, child: const Text('Buy')),
        ],
      ),
    );
  }
}
