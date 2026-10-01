part of 'farm_bloc.dart';

sealed class FarmEvent extends Equatable {
  const FarmEvent();
  @override
  List<Object?> get props => [];
}

class FarmRequested extends FarmEvent {
  final String wallet;
  const FarmRequested(this.wallet);
  @override
  List<Object?> get props => [wallet];
}

class FarmCreatureFed extends FarmEvent {
  final int tokenId;
  const FarmCreatureFed(this.tokenId);
  @override
  List<Object?> get props => [tokenId];
}

class FarmEggCollected extends FarmEvent {
  final int creatureTokenId;
  const FarmEggCollected(this.creatureTokenId);
  @override
  List<Object?> get props => [creatureTokenId];
}

class FarmEggHatched extends FarmEvent {
  final int eggTokenId;
  const FarmEggHatched(this.eggTokenId);
  @override
  List<Object?> get props => [eggTokenId];
}

class FarmRottenEggDiscarded extends FarmEvent {
  final int eggTokenId;
  const FarmRottenEggDiscarded(this.eggTokenId);
  @override
  List<Object?> get props => [eggTokenId];
}

class FarmCreaturePurchased extends FarmEvent {
  final int rarityTier;
  final double priceArb;
  const FarmCreaturePurchased(this.rarityTier, this.priceArb);
  @override
  List<Object?> get props => [rarityTier, priceArb];
}
