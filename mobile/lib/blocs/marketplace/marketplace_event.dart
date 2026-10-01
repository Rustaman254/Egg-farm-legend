part of 'marketplace_bloc.dart';

sealed class MarketplaceEvent extends Equatable {
  const MarketplaceEvent();
  @override
  List<Object?> get props => [];
}

class ListingsRequested extends MarketplaceEvent {
  final String? kind;
  const ListingsRequested({this.kind});
  @override
  List<Object?> get props => [kind];
}

class ListingPurchased extends MarketplaceEvent {
  final Listing listing;
  const ListingPurchased(this.listing);
  @override
  List<Object?> get props => [listing.listingId];
}

class ListingCancelled extends MarketplaceEvent {
  final int listingId;
  const ListingCancelled(this.listingId);
  @override
  List<Object?> get props => [listingId];
}

class ItemListed extends MarketplaceEvent {
  final bool isEgg;
  final int tokenId;
  final String priceArb;
  const ItemListed({required this.isEgg, required this.tokenId, required this.priceArb});
  @override
  List<Object?> get props => [isEgg, tokenId, priceArb];
}
