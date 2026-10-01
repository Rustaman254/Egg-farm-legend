import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/marketplace/marketplace_bloc.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/listing.dart';
import '../widgets/brand_app_bar.dart';
import '../widgets/pill_filter_chip.dart';

class MarketplaceScreen extends StatefulWidget {
  final String wallet;
  const MarketplaceScreen({super.key, required this.wallet});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  String? _kindFilter;

  @override
  void initState() {
    super.initState();
    context.read<MarketplaceBloc>().add(const ListingsRequested());
  }

  void _setFilter(String? kind) {
    setState(() => _kindFilter = kind);
    context.read<MarketplaceBloc>().add(ListingsRequested(kind: kind));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BrandAppBar(title: 'Marketplace', icon: Icons.storefront),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                PillFilterChip(label: 'All', selected: _kindFilter == null, onTap: () => _setFilter(null)),
                const SizedBox(width: 8),
                PillFilterChip(label: '🥚 Eggs', selected: _kindFilter == 'egg', onTap: () => _setFilter('egg')),
                const SizedBox(width: 8),
                PillFilterChip(label: '🐔 Creatures', selected: _kindFilter == 'creature', onTap: () => _setFilter('creature')),
              ],
            ),
          ),
          Expanded(
            child: BlocConsumer<MarketplaceBloc, MarketplaceState>(
              listener: (context, state) {
                if (state is MarketplaceLoaded && state.error != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(state.error!), backgroundColor: AppColors.danger),
                  );
                }
              },
              builder: (context, state) {
                if (state is MarketplaceLoading || state is MarketplaceInitial) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                }
                if (state is MarketplaceError) {
                  return Center(child: Text(state.message));
                }
                final loaded = state as MarketplaceLoaded;
                if (loaded.listings.isEmpty) {
                  return const Center(child: Text('No listings yet. Be the first to sell!'));
                }

                return RefreshIndicator(
                  onRefresh: () async => context.read<MarketplaceBloc>().add(ListingsRequested(kind: _kindFilter)),
                  child: GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.72,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: loaded.listings.length,
                    itemBuilder: (context, index) {
                      final listing = loaded.listings[index];
                      final isMine = listing.sellerAddress.toLowerCase() == widget.wallet.toLowerCase();
                      final isPending = loaded.pendingListingId == listing.listingId;
                      return _ListingCard(
                        listing: listing,
                        isMine: isMine,
                        isPending: isPending,
                        onBuy: () => context.read<MarketplaceBloc>().add(ListingPurchased(listing)),
                        onCancel: () => context.read<MarketplaceBloc>().add(ListingCancelled(listing.listingId)),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Mirrors the webapp's ListingCard: rarity-colored border, price badge, glossy art frame,
/// seller line, footer action. The mobile Listing model doesn't carry species/rarity/nickname
/// yet (see data/models/listing.dart), so this renders a generic kind icon rather than the
/// webapp's per-creature/egg art -- a data-layer gap, not a styling one.
class _ListingCard extends StatelessWidget {
  final Listing listing;
  final bool isMine;
  final bool isPending;
  final VoidCallback onBuy;
  final VoidCallback onCancel;

  const _ListingCard({
    required this.listing,
    required this.isMine,
    required this.isPending,
    required this.onBuy,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final isEgg = listing.kind == 'egg';
    final emoji = isEgg ? '🥚' : '🐔';

    return Container(
      decoration: cardPopDecoration(borderColor: AppColors.border, small: true),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${isEgg ? "Egg" : "Creature"} #${listing.tokenId}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(8)),
                child: Text('${listing.priceInArb} ARB', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: RadialGradient(colors: [AppColors.border.withValues(alpha: 0.5), AppColors.border.withValues(alpha: 0.12)]),
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 40)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isMine ? 'Your listing' : 'Seller: ${_shortAddress(listing.sellerAddress)}',
            style: const TextStyle(fontSize: 10, color: AppColors.textFaint),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 34,
            child: isPending
                ? const Center(child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                : isMine
                    ? OutlinedButton(onPressed: onCancel, child: const Text('Cancel', style: TextStyle(fontSize: 11)))
                    : ElevatedButton(
                        onPressed: onBuy,
                        style: ElevatedButton.styleFrom(padding: EdgeInsets.zero),
                        child: const Text('Buy', style: TextStyle(fontSize: 12)),
                      ),
          ),
        ],
      ),
    );
  }

  String _shortAddress(String address) {
    if (address.length < 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }
}
