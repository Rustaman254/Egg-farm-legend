import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web3dart/web3dart.dart';
import '../../core/blockchain/local_signer_service.dart';
import '../../core/blockchain/transaction_signer.dart';
import '../../core/network/api_client.dart';

/// Registration/login for the app's built-in wallet, plus the "stay logged in" local session:
/// once a private key is recovered (at register, at login, or from the last session), its raw
/// hex is cached in OS-keychain-backed secure storage so the app doesn't ask for a password
/// every launch -- the same convenience a normal wallet app gives you after its first unlock.
class AuthRepository {
  final ApiClient api;
  final LocalSignerService signer;
  final ActiveSigner activeSigner;
  final _storage = const FlutterSecureStorage();

  static const _keyPrivateKey = 'eggfarm.wallet.privateKey';
  static const _keyUsername = 'eggfarm.wallet.username';

  AuthRepository({required this.api, required this.signer, required this.activeSigner});

  /// Registers a brand-new account: generates a wallet on-device, encrypts it with [password],
  /// registers the resulting address with the backend, and unlocks the session.
  Future<String> register({required String username, required String email, required String password}) async {
    final (address, keystoreJson) = signer.createAndEncrypt(password);
    await api.register(username: username, email: email, password: password, walletAddress: address, walletBackup: keystoreJson);
    activeSigner.current = signer;
    await _persistSession(username: username);
    return address;
  }

  /// Logs in with email+password: the backend hands back the encrypted keystore, which is
  /// decrypted here, locally, with the same password -- the backend never sees the raw key.
  Future<String> login({required String email, required String password}) async {
    final result = await api.login(email: email, password: password);
    final keystoreJson = result['walletBackup'] as String;
    final username = result['username'] as String;
    signer.unlock(keystoreJson, password);
    activeSigner.current = signer;
    await _persistSession(username: username);
    return result['walletAddress'] as String;
  }

  /// Resumes the last session without a password, if one was saved on this device.
  Future<String?> tryResumeSession() async {
    final hex = await _storage.read(key: _keyPrivateKey);
    if (hex == null) return null;
    final credentials = EthPrivateKey.fromHex(hex);
    signer.unlockWithCredentials(credentials);
    activeSigner.current = signer;
    return credentials.address.hexEip55;
  }

  Future<String?> get savedUsername => _storage.read(key: _keyUsername);

  Future<void> logout() async {
    signer.lock();
    activeSigner.current = null;
    await _storage.delete(key: _keyPrivateKey);
    await _storage.delete(key: _keyUsername);
  }

  Future<void> _persistSession({required String username}) async {
    final hex = signer.exportPrivateKeyHex();
    if (hex == null) return;
    await _storage.write(key: _keyPrivateKey, value: hex);
    await _storage.write(key: _keyUsername, value: username);
  }
}
