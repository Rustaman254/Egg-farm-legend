/// A source of signed transactions -- either the connected WalletConnect wallet (see
/// [WalletService]) or the app's own locally-held key (see [LocalSignerService]).
/// [ContractService] talks to whichever is active without needing to know which.
abstract class TransactionSigner {
  /// The signing wallet's address, or null if nothing is connected/unlocked.
  String? get address;

  /// Signs and broadcasts a transaction, returning its hash once accepted by the node/wallet.
  /// `data` is ABI-encoded calldata (hex, 0x-prefixed).
  Future<String> sendTransaction({required String to, required String data, BigInt? valueWei});
}

/// Holds whichever [TransactionSigner] is currently active (the built-in wallet after
/// register/login, or WalletConnect after a manual connect) so [ContractService] can be wired up
/// once at DI time instead of being re-created when the user switches between the two.
class ActiveSigner implements TransactionSigner {
  TransactionSigner? current;

  @override
  String? get address => current?.address;

  @override
  Future<String> sendTransaction({required String to, required String data, BigInt? valueWei}) {
    final signer = current;
    if (signer == null) {
      throw StateError('No wallet available -- register, log in, or connect a wallet first.');
    }
    return signer.sendTransaction(to: to, data: data, valueWei: valueWei);
  }
}
