import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/models/listing.dart';
import '../../data/repositories/marketplace_repository.dart';

part 'marketplace_event.dart';
part 'marketplace_state.dart';

class MarketplaceBloc extends Bloc<MarketplaceEvent, MarketplaceState> {
  final MarketplaceRepository repository;
  String? _kindFilter;

  MarketplaceBloc(this.repository) : super(const MarketplaceInitial()) {
    on<ListingsRequested>(_onRequested);
    on<ListingPurchased>(_onPurchased);
    on<ListingCancelled>(_onCancelled);
    on<ItemListed>(_onItemListed);
  }

  Future<void> _onRequested(ListingsRequested event, Emitter<MarketplaceState> emit) async {
    _kindFilter = event.kind;
    emit(const MarketplaceLoading());
    await _reload(emit);
  }

  Future<void> _reload(Emitter<MarketplaceState> emit) async {
    try {
      final listings = await repository.listListings(kind: _kindFilter);
      emit(MarketplaceLoaded(listings));
    } catch (e) {
      emit(MarketplaceError(e.toString()));
    }
  }

  Future<void> _onPurchased(ListingPurchased event, Emitter<MarketplaceState> emit) async {
    final current = state;
    if (current is! MarketplaceLoaded) return;
    emit(current.copyWith(pendingListingId: event.listing.listingId, clearError: true));
    try {
      await repository.buyListing(event.listing);
      await Future.delayed(const Duration(seconds: 2));
      await _reload(emit);
    } catch (e) {
      final latest = state;
      if (latest is MarketplaceLoaded) {
        emit(latest.copyWith(clearPending: true, error: e.toString()));
      }
    }
  }

  Future<void> _onCancelled(ListingCancelled event, Emitter<MarketplaceState> emit) async {
    final current = state;
    if (current is! MarketplaceLoaded) return;
    emit(current.copyWith(pendingListingId: event.listingId, clearError: true));
    try {
      await repository.cancelListing(event.listingId);
      await Future.delayed(const Duration(seconds: 2));
      await _reload(emit);
    } catch (e) {
      final latest = state;
      if (latest is MarketplaceLoaded) {
        emit(latest.copyWith(clearPending: true, error: e.toString()));
      }
    }
  }

  Future<void> _onItemListed(ItemListed event, Emitter<MarketplaceState> emit) async {
    final current = state;
    if (current is! MarketplaceLoaded) return;
    emit(current.copyWith(isListing: true, clearError: true));
    try {
      await repository.listItem(isEgg: event.isEgg, tokenId: event.tokenId, priceArb: event.priceArb);
      await Future.delayed(const Duration(seconds: 2));
      await _reload(emit);
    } catch (e) {
      final latest = state;
      if (latest is MarketplaceLoaded) {
        emit(latest.copyWith(isListing: false, error: e.toString()));
      }
    }
  }
}
