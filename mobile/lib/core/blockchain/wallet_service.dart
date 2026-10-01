import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';
import '../constants/app_constants.dart';
import 'transaction_signer.dart';

/// Wraps WalletConnect v2 pairing + signing so the rest of the app only deals with
/// "connect / disconnect / send a transaction", not relay/session plumbing. This is the
/// alternative signer for players who'd rather bring their own wallet app (MetaMask, Rainbow,
/// etc.) instead of the built-in one -- see LocalSignerService for that default path.
///
/// NOTE: this talks to a real WalletConnect relay and a real mobile wallet -- it cannot be
/// exercised headlessly in CI/CD. Validate the full connect -> approve -> sign flow on-device
/// against Arbitrum Sepolia before demo day.
class WalletService implements TransactionSigner {
  Web3App? _web3App;
  SessionData? _session;

  bool get isConnected => _session != null;

  String? get connectedAddress {
    final accounts = _session?.namespaces['eip155']?.accounts;
    if (accounts == null || accounts.isEmpty) return null;
    // Account strings are CAIP-10: "eip155:421614:0xabc...".
    return accounts.first.split(':').last;
  }

  @override
  String? get address => connectedAddress;

  Future<void> init() async {
    if (_web3App != null) return;
    _web3App = await Web3App.createInstance(
      projectId: ChainConfig.walletConnectProjectId,
      metadata: const PairingMetadata(
        name: 'EggFarm Legends',
        description: 'Play-to-earn creature breeding on Arbitrum',
        url: 'https://eggfarm.legends',
        icons: ['https://eggfarm.legends/icon.png'],
      ),
    );
  }

  /// Starts a new pairing. Returns the wc: URI to render as a QR code (desktop wallet) or open
  /// as a deep link (mobile wallet app installed on the same device). Completes once the wallet
  /// approves the session.
  Future<String> connect({required void Function(String uri) onPairingUri}) async {
    await init();
    final app = _web3App!;

    final resp = await app.connect(
      requiredNamespaces: {
        'eip155': RequiredNamespace(
          chains: [ChainConfig.caip2ChainId],
          methods: const ['eth_sendTransaction', 'personal_sign', 'eth_signTypedData'],
          events: const ['chainChanged', 'accountsChanged'],
        ),
      },
    );

    if (resp.uri != null) {
      onPairingUri(resp.uri.toString());
    }

    _session = await resp.session.future;
    return connectedAddress!;
  }

  Future<void> disconnect() async {
    final app = _web3App;
    final session = _session;
    if (app == null || session == null) return;
    await app.disconnectSession(
      topic: session.topic,
      reason: const WalletConnectError(code: 6000, message: 'User disconnected'),
    );
    _session = null;
  }

  /// Sends a transaction through the connected wallet and returns the tx hash once the user
  /// approves it in their wallet app. `data` is ABI-encoded calldata (hex, 0x-prefixed).
  @override
  Future<String> sendTransaction({
    required String to,
    required String data,
    BigInt? valueWei,
  }) async {
    final app = _web3App;
    final session = _session;
    if (app == null || session == null) {
      throw StateError('Wallet not connected');
    }

    final params = {
      'from': connectedAddress,
      'to': to,
      'data': data,
      if (valueWei != null && valueWei > BigInt.zero) 'value': '0x${valueWei.toRadixString(16)}',
    };

    final result = await app.request(
      topic: session.topic,
      chainId: ChainConfig.caip2ChainId,
      request: SessionRequestParams(
        method: 'eth_sendTransaction',
        params: [params],
      ),
    );

    return result as String; // tx hash
  }
}
