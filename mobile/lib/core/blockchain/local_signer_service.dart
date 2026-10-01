import 'dart:math';
import 'package:http/http.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';
import '../constants/app_constants.dart';
import 'transaction_signer.dart';

/// The app's built-in wallet: an Ethereum keypair generated on-device, signed with locally --
/// no external wallet app, no popup. The private key never leaves the device; only a
/// password-encrypted Ethereum V3 keystore (see [createAndEncrypt]/[decrypt]) is ever sent to
/// the backend, and only so a later login on a new device can recover it.
class LocalSignerService implements TransactionSigner {
  final Web3Client _client;
  EthPrivateKey? _credentials;

  LocalSignerService({Web3Client? client}) : _client = client ?? Web3Client(ChainConfig.rpcUrl, Client());

  bool get isUnlocked => _credentials != null;

  @override
  String? get address => _credentials?.address.hexEip55;

  /// Generates a brand-new wallet and encrypts it with [password], returning the address and the
  /// keystore JSON to send to the backend at registration. Also unlocks this signer immediately
  /// so the new account can start playing right away.
  (String address, String keystoreJson) createAndEncrypt(String password) {
    final random = Random.secure();
    final credentials = EthPrivateKey.createRandom(random);
    final wallet = Wallet.createNew(credentials, password, random);
    _credentials = credentials;
    return (credentials.address.hexEip55, wallet.toJson());
  }

  /// Decrypts a keystore JSON (from registration or a login response) with [password] and
  /// unlocks this signer. Throws if the password is wrong for that keystore.
  void unlock(String keystoreJson, String password) {
    final wallet = Wallet.fromJson(keystoreJson, password);
    _credentials = wallet.privateKey;
  }

  /// Unlocks directly from an already-recovered key -- used to resume a session from the raw
  /// key cached in secure storage, without needing the password again.
  void unlockWithCredentials(EthPrivateKey credentials) => _credentials = credentials;

  /// The raw private key hex, for caching in secure storage so the app can resume the session
  /// without a password next launch. Never sent anywhere over the network.
  String? exportPrivateKeyHex() {
    final creds = _credentials;
    if (creds == null) return null;
    return bytesToHex(creds.privateKey, include0x: true);
  }

  void lock() => _credentials = null;

  @override
  Future<String> sendTransaction({required String to, required String data, BigInt? valueWei}) async {
    final creds = _credentials;
    if (creds == null) {
      throw StateError('Wallet locked -- log in again.');
    }
    return _client.sendTransaction(
      creds,
      Transaction(
        to: EthereumAddress.fromHex(to),
        value: EtherAmount.inWei(valueWei ?? BigInt.zero),
        data: hexToBytes(data),
        maxGas: 500000,
      ),
      chainId: ChainConfig.chainId,
    );
  }
}
