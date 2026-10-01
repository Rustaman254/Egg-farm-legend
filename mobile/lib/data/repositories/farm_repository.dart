import '../../core/blockchain/contract_service.dart';
import '../../core/network/api_client.dart';
import '../models/creature.dart';
import '../models/egg.dart';

class FarmSnapshot {
  final List<Creature> creatures;
  final List<Egg> eggs;
  final String feedBalance;
  const FarmSnapshot({required this.creatures, required this.eggs, required this.feedBalance});
}

/// Mediates between the backend's cached farm state (fast reads) and the on-chain contracts
/// (the source of truth for writes). Every write method returns the tx hash so the UI can show
/// "pending" feedback while the backend indexer catches up and the next getFarm() reflects it.
class FarmRepository {
  final ApiClient api;
  final ContractService contracts;

  FarmRepository({required this.api, required this.contracts});

  Future<FarmSnapshot> getFarm(String wallet) async {
    final json = await api.getFarm(wallet);
    final creatures = (json['creatures'] as List<dynamic>? ?? [])
        .map((e) => Creature.fromJson(e as Map<String, dynamic>))
        .toList();
    final eggs = (json['eggs'] as List<dynamic>? ?? [])
        .map((e) => Egg.fromJson(e as Map<String, dynamic>))
        .toList();
    return FarmSnapshot(creatures: creatures, eggs: eggs, feedBalance: json['feedBalance'] as String? ?? '0');
  }

  Future<String> feedCreature(int tokenId) => contracts.feedCreature(tokenId);

  Future<String> layEgg(int tokenId) => contracts.layEgg(tokenId);

  Future<String> hatchEgg(int tokenId) => contracts.hatchEgg(tokenId);

  Future<String> discardRottenEgg(int tokenId) => contracts.discardRottenEgg(tokenId);

  Future<String> purchaseCreature(int rarityTier, double priceArb) =>
      contracts.purchaseCreature(rarityTier, priceArb);

  Future<String> breedCreatures(int parent1, int parent2) => contracts.breedCreatures(parent1, parent2);
}
