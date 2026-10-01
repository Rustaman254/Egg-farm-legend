import 'package:http/http.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';
import '../constants/app_constants.dart';
import 'contract_abis.dart';
import 'transaction_signer.dart';

/// Encodes calldata for each player-initiated contract call with web3dart, then hands it to
/// whichever [TransactionSigner] is currently active -- the app's own built-in wallet by
/// default, or a connected external wallet (WalletConnect) if the player chose that instead.
class ContractService {
  final TransactionSigner wallet;
  final Web3Client _readClient;

  ContractService(this.wallet, {Web3Client? readClient})
      : _readClient = readClient ?? Web3Client(ChainConfig.rpcUrl, Client());

  late final _feedToken = DeployedContract(
    ContractAbi.fromJson(ContractAbis.feedToken, 'FeedToken'),
    EthereumAddress.fromHex(ChainConfig.feedTokenAddress),
  );
  late final _creatureNft = DeployedContract(
    ContractAbi.fromJson(ContractAbis.creatureNft, 'CreatureNFT'),
    EthereumAddress.fromHex(ChainConfig.creatureNftAddress),
  );
  late final _eggNft = DeployedContract(
    ContractAbi.fromJson(ContractAbis.eggNft, 'EggNFT'),
    EthereumAddress.fromHex(ChainConfig.eggNftAddress),
  );
  late final _marketplace = DeployedContract(
    ContractAbi.fromJson(ContractAbis.marketplace, 'Marketplace'),
    EthereumAddress.fromHex(ChainConfig.marketplaceAddress),
  );

  static BigInt _arb(double amount) => BigInt.from((amount * 1e18).round());

  Future<String> purchaseCreature(int rarityTier, double priceArb) {
    return _call(_creatureNft, 'purchaseCreature', [BigInt.from(rarityTier)], value: _arb(priceArb));
  }

  Future<String> feedCreature(int tokenId) {
    return _call(_creatureNft, 'feedCreature', [BigInt.from(tokenId)]);
  }

  Future<String> layEgg(int tokenId) {
    return _call(_creatureNft, 'layEgg', [BigInt.from(tokenId)]);
  }

  Future<String> breedCreatures(int parent1, int parent2) {
    return _call(_creatureNft, 'breedCreatures', [BigInt.from(parent1), BigInt.from(parent2)],
        value: _arb(GameConstants.breedArbCost));
  }

  Future<String> hatchEgg(int tokenId) {
    return _call(_eggNft, 'hatchEgg', [BigInt.from(tokenId)]);
  }

  Future<String> discardRottenEgg(int tokenId) {
    return _call(_eggNft, 'discardRottenEgg', [BigInt.from(tokenId)]);
  }

  Future<String> approveCreatureForMarketplace(int tokenId) {
    return _call(_creatureNft, 'approve', [EthereumAddress.fromHex(ChainConfig.marketplaceAddress), BigInt.from(tokenId)]);
  }

  Future<String> approveEggForMarketplace(int tokenId) {
    return _call(_eggNft, 'approve', [EthereumAddress.fromHex(ChainConfig.marketplaceAddress), BigInt.from(tokenId)]);
  }

  Future<String> listOnMarketplace({required bool isEgg, required int tokenId, required BigInt priceWei}) {
    final nftAddress = EthereumAddress.fromHex(isEgg ? ChainConfig.eggNftAddress : ChainConfig.creatureNftAddress);
    return _call(_marketplace, 'listEgg', [nftAddress, BigInt.from(tokenId), priceWei]);
  }

  Future<String> buyListing(int listingId, BigInt priceWei) {
    return _call(_marketplace, 'buyEgg', [BigInt.from(listingId)], value: priceWei);
  }

  Future<String> cancelListing(int listingId) {
    return _call(_marketplace, 'cancelListing', [BigInt.from(listingId)]);
  }

  /// Reads a player's live on-chain $FEED balance directly from the RPC node -- a fallback for
  /// when the backend's cached balance (returned by /api/players/{wallet}/farm) is stale.
  Future<BigInt> getFeedBalance(String wallet) async {
    final function = _feedToken.function('balanceOf');
    final result = await _readClient.call(
      contract: _feedToken,
      function: function,
      params: [EthereumAddress.fromHex(wallet)],
    );
    return result.first as BigInt;
  }

  Future<String> _call(DeployedContract contract, String functionName, List<dynamic> params, {BigInt? value}) async {
    final function = contract.function(functionName);
    final data = function.encodeCall(params);
    return wallet.sendTransaction(
      to: contract.address.hexEip55,
      data: bytesToHex(data, include0x: true),
      valueWei: value,
    );
  }
}
