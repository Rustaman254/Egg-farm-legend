import '../../core/blockchain/contract_service.dart';
import '../../core/network/api_client.dart';
import '../models/listing.dart';

class MarketplaceRepository {
  final ApiClient api;
  final ContractService contracts;

  MarketplaceRepository({required this.api, required this.contracts});

  Future<List<Listing>> listListings({String? kind}) async {
    final json = await api.listMarketplaceListings(kind: kind);
    return json.map((e) => Listing.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Lists an NFT for sale: approve() then listEgg() -- two wallet-signed txs, since the
  /// Marketplace contract escrows the NFT and needs prior ERC-721 approval to pull it.
  Future<void> listItem({required bool isEgg, required int tokenId, required String priceArb}) async {
    if (isEgg) {
      await contracts.approveEggForMarketplace(tokenId);
    } else {
      await contracts.approveCreatureForMarketplace(tokenId);
    }
    await contracts.listOnMarketplace(isEgg: isEgg, tokenId: tokenId, priceWei: arbToWei(priceArb));
  }

  Future<String> buyListing(Listing listing) {
    return contracts.buyListing(listing.listingId, BigInt.parse(listing.priceWei));
  }

  Future<String> cancelListing(int listingId) => contracts.cancelListing(listingId);
}
