import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/dex/dex_cubit.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/dex_entry.dart';
import '../widgets/brand_app_bar.dart';
import '../widgets/pill_filter_chip.dart';

const _tierFilters = [
  (label: 'All', tier: null),
  (label: 'Common', tier: 1),
  (label: 'Uncommon', tier: 2),
  (label: 'Rare', tier: 3),
  (label: 'Epic', tier: 4),
  (label: 'Legendary', tier: 5),
];

/// Species Dex -- mirrors the webapp's CollectionPage. Every species a player has ever owned
/// stays discovered here even after selling/breeding it away (see backend dex service), so this
/// is a permanent record, unlike the Farm screen's live creature list.
class CollectionScreen extends StatefulWidget {
  final String wallet;
  const CollectionScreen({super.key, required this.wallet});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  int? _tierFilter;

  @override
  void initState() {
    super.initState();
    context.read<DexCubit>().load(widget.wallet);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BrandAppBar(title: 'Species Dex', icon: Icons.menu_book),
      body: BlocBuilder<DexCubit, DexState>(
        builder: (context, state) {
          if (state is DexLoading || state is DexInitial) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }
          if (state is DexError) {
            return Center(child: Text(state.message));
          }
          final entries = (state as DexLoaded).entries;
          final discoveredCount = entries.where((e) => e.discovered).length;
          final total = entries.isEmpty ? 40 : entries.length;
          final filtered = _tierFilter == null ? entries : entries.where((e) => e.tier == _tierFilter).toList();

          return RefreshIndicator(
            onRefresh: () => context.read<DexCubit>().load(widget.wallet),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _ProgressCard(discoveredCount: discoveredCount, total: total),
                const SizedBox(height: 12),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _tierFilters.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final f = _tierFilters[index];
                      return PillFilterChip(
                        label: f.label,
                        selected: _tierFilter == f.tier,
                        onTap: () => setState(() => _tierFilter = f.tier),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.78,
                  ),
                  itemBuilder: (context, index) => _DexTile(entry: filtered[index]),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final int discoveredCount;
  final int total;
  const _ProgressCard({required this.discoveredCount, required this.total});

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : discoveredCount / total;
    return Container(
      decoration: cardPopDecoration(borderColor: AppColors.primary),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Collection Progress', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  '$discoveredCount / $total',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: AppColors.surface2,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Every species you've ever owned stays in your dex -- selling, breeding away, or "
              "losing an Animora to starvation never un-discovers it.",
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _DexTile extends StatelessWidget {
  final DexEntry entry;
  const _DexTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final number = entry.species.toString().padLeft(3, '0');
    final rarityColor = AppColors.forRarity(entry.tier);

    if (!entry.discovered) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 2),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('No. $number', style: const TextStyle(fontSize: 9, color: AppColors.textFaint, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.textFaint, width: 2, style: BorderStyle.solid),
              ),
              alignment: Alignment.center,
              child: const Text('?', style: TextStyle(fontSize: 20, color: AppColors.textFaint)),
            ),
            const SizedBox(height: 6),
            const Text('???', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textFaint)),
            Text(GameConstants.rarityLabels[entry.tier], style: const TextStyle(fontSize: 9, color: AppColors.textFaint)),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: rarityColor, width: 2),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('No. $number', style: const TextStyle(fontSize: 9, color: AppColors.textFaint, fontWeight: FontWeight.bold)),
              if (entry.ownedCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(8)),
                  child: Text('x${entry.ownedCount}', style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(shape: BoxShape.circle, color: rarityColor.withValues(alpha: 0.15), border: Border.all(color: rarityColor, width: 2)),
            alignment: Alignment.center,
            child: Text(GameConstants.speciesEmojiFor(entry.species), style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(height: 6),
          Text(
            GameConstants.speciesName(entry.species),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(GameConstants.rarityLabels[entry.tier], style: TextStyle(fontSize: 9, color: rarityColor, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
