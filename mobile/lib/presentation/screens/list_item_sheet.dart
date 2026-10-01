import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/marketplace/marketplace_bloc.dart';
import '../../core/theme/app_theme.dart';

void showListItemSheet(BuildContext context, {required bool isEgg, required int tokenId}) {
  final marketplaceBloc = context.read<MarketplaceBloc>();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetContext) => BlocProvider.value(
      value: marketplaceBloc,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: _ListItemForm(isEgg: isEgg, tokenId: tokenId),
      ),
    ),
  );
}

class _ListItemForm extends StatefulWidget {
  final bool isEgg;
  final int tokenId;
  const _ListItemForm({required this.isEgg, required this.tokenId});

  @override
  State<_ListItemForm> createState() => _ListItemFormState();
}

class _ListItemFormState extends State<_ListItemForm> {
  final _priceController = TextEditingController();

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'List ${widget.isEgg ? "Egg" : "Creature"} #${widget.tokenId}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          const Text('This requires two wallet approvals: one to allow the marketplace to hold your NFT, one to confirm the listing.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
          const SizedBox(height: 16),
          TextField(
            controller: _priceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Price (ARB)',
              border: OutlineInputBorder(),
              hintText: '0.15',
            ),
          ),
          const SizedBox(height: 16),
          BlocConsumer<MarketplaceBloc, MarketplaceState>(
            listener: (context, state) {
              if (state is MarketplaceLoaded && state.error != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(state.error!), backgroundColor: AppColors.danger),
                );
              }
            },
            builder: (context, state) {
              final isListing = state is MarketplaceLoaded && state.isListing;
              return SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isListing
                      ? null
                      : () {
                          final price = _priceController.text.trim();
                          if (price.isEmpty) return;
                          context.read<MarketplaceBloc>().add(
                                ItemListed(isEgg: widget.isEgg, tokenId: widget.tokenId, priceArb: price),
                              );
                          Navigator.of(context).pop();
                        },
                  child: isListing
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('List for Sale'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
