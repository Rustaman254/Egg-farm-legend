part of 'marketplace_bloc.dart';

sealed class MarketplaceState extends Equatable {
  const MarketplaceState();
  @override
  List<Object?> get props => [];
}

class MarketplaceInitial extends MarketplaceState {
  const MarketplaceInitial();
}

class MarketplaceLoading extends MarketplaceState {
  const MarketplaceLoading();
}

class MarketplaceLoaded extends MarketplaceState {
  final List<Listing> listings;
  final int? pendingListingId;
  final bool isListing;
  final String? error;

  const MarketplaceLoaded(this.listings, {this.pendingListingId, this.isListing = false, this.error});

  MarketplaceLoaded copyWith({
    List<Listing>? listings,
    int? pendingListingId,
    bool clearPending = false,
    bool? isListing,
    String? error,
    bool clearError = false,
  }) {
    return MarketplaceLoaded(
      listings ?? this.listings,
      pendingListingId: clearPending ? null : (pendingListingId ?? this.pendingListingId),
      isListing: isListing ?? this.isListing,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [listings, pendingListingId, isListing, error];
}

class MarketplaceError extends MarketplaceState {
  final String message;
  const MarketplaceError(this.message);
  @override
  List<Object?> get props => [message];
}
