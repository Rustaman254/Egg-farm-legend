import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/app_constants.dart';

/// Thin wrapper around the Go backend's REST API (see backend/openapi.yaml).
class ApiClient {
  final http.Client _http;
  final String baseUrl;

  ApiClient({http.Client? client, this.baseUrl = ApiConfig.baseUrl}) : _http = client ?? http.Client();

  Future<Map<String, dynamic>> getFarm(String wallet) async {
    final res = await _get('/api/players/$wallet/farm');
    return res as Map<String, dynamic>;
  }

  Future<void> recordLogin(String wallet) async {
    await _post('/api/players/$wallet/login', {});
  }

  // ---------------------------------------------------------------------
  // Auth: the built-in wallet's account system (see internal/services/auth). The backend never
  // sees a usable private key -- walletBackup is a password-encrypted keystore, opaque here.
  // ---------------------------------------------------------------------

  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String walletAddress,
    required String walletBackup,
  }) async {
    final res = await _post('/api/auth/register', {
      'username': username,
      'email': email,
      'password': password,
      'walletAddress': walletAddress,
      'walletBackup': walletBackup,
    });
    return res as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> login({required String email, required String password}) async {
    final res = await _post('/api/auth/login', {'email': email, 'password': password});
    return res as Map<String, dynamic>;
  }

  Future<List<dynamic>> listTasks(String wallet) async {
    final res = await _get('/api/tasks/$wallet');
    return res as List<dynamic>;
  }

  Future<String> claimTask(String wallet, String taskId) async {
    final res = await _post('/api/tasks/$wallet/$taskId/claim', {});
    return (res as Map<String, dynamic>)['txHash'] as String? ?? '';
  }

  Future<Map<String, dynamic>> previewEggOdds(int happiness) async {
    final res = await _get('/api/eggs/preview?happiness=$happiness');
    return res as Map<String, dynamic>;
  }

  Future<List<dynamic>> listMarketplaceListings({String? kind}) async {
    final query = kind != null ? '?kind=$kind' : '';
    final res = await _get('/api/marketplace/listings$query');
    return res as List<dynamic>;
  }

  Future<List<dynamic>> topEarners() async {
    final res = await _get('/api/leaderboard/top-earners');
    return res as List<dynamic>;
  }

  Future<List<dynamic>> topBattlers() async {
    final res = await _get('/api/leaderboard/top-battlers');
    return res as List<dynamic>;
  }

  Future<List<dynamic>> getDex(String wallet) async {
    final res = await _get('/api/players/$wallet/dex');
    return res as List<dynamic>;
  }

  Future<Map<String, dynamic>> activity(String wallet) async {
    final res = await _get('/api/players/$wallet/activity');
    return res as Map<String, dynamic>;
  }

  // ---------------------------------------------------------------------
  // Battle Arena: PvE, PvP challenges (open board + direct + wagers), presence.
  // ---------------------------------------------------------------------

  Future<Map<String, dynamic>> fightBattle(String wallet, int creatureTokenId) async {
    final res = await _post('/api/players/$wallet/battles', {'creatureTokenId': creatureTokenId});
    return res as Map<String, dynamic>;
  }

  Future<List<dynamic>> listBattles(String wallet) async {
    final res = await _get('/api/players/$wallet/battles');
    return res as List<dynamic>;
  }

  Future<void> arenaHeartbeat(String wallet) async {
    await _post('/api/players/$wallet/arena/heartbeat', {});
  }

  Future<List<dynamic>> onlinePlayers() async {
    final res = await _get('/api/arena/online');
    return res as List<dynamic>;
  }

  Future<List<dynamic>> openChallenges() async {
    final res = await _get('/api/arena/challenges');
    return res as List<dynamic>;
  }

  Future<List<dynamic>> myChallenges(String wallet) async {
    final res = await _get('/api/players/$wallet/challenges');
    return res as List<dynamic>;
  }

  Future<List<dynamic>> incomingChallenges(String wallet) async {
    final res = await _get('/api/players/$wallet/challenges/incoming');
    return res as List<dynamic>;
  }

  // wagerWei: native-currency (ETH/ARB) wei-string -- see BattleEscrow.sol. Mobile doesn't yet
  // stake an on-chain escrow (that's built for the webapp only so far), so this always sends "0"
  // for now; wiring it up is a follow-up.
  Future<Map<String, dynamic>> createChallenge(
    String wallet,
    int creatureTokenId, {
    String? challengedWallet,
    String wagerWei = '0',
  }) async {
    final res = await _post('/api/players/$wallet/challenges', {
      'creatureTokenId': creatureTokenId,
      'challengedWallet': challengedWallet ?? '',
      'wagerWei': wagerWei,
    });
    return res as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> acceptChallenge(String wallet, int challengeId, int creatureTokenId) async {
    final res = await _post('/api/players/$wallet/challenges/$challengeId/accept', {'creatureTokenId': creatureTokenId});
    return res as Map<String, dynamic>;
  }

  Future<void> cancelChallenge(String wallet, int challengeId) async {
    await _post('/api/players/$wallet/challenges/$challengeId/cancel', {});
  }

  Future<List<dynamic>> abilityCatalog() async {
    final res = await _get('/api/abilities');
    return res as List<dynamic>;
  }

  // Harmless against the real backend; only matters when baseUrl points at an ngrok free-tier
  // tunnel for local dev, which otherwise serves an HTML "visit site" interstitial instead of
  // the actual JSON response.
  static const _ngrokSkipWarningHeader = {'ngrok-skip-browser-warning': 'true'};

  Future<dynamic> _get(String path) async {
    final res = await _http.get(Uri.parse('$baseUrl$path'), headers: _ngrokSkipWarningHeader);
    _throwIfError(res);
    return jsonDecode(res.body);
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final res = await _http.post(
      Uri.parse('$baseUrl$path'),
      headers: {'Content-Type': 'application/json', ..._ngrokSkipWarningHeader},
      body: jsonEncode(body),
    );
    _throwIfError(res);
    return jsonDecode(res.body);
  }

  void _throwIfError(http.Response res) {
    if (res.statusCode >= 400) {
      String message = res.body;
      try {
        message = (jsonDecode(res.body) as Map<String, dynamic>)['error'] as String? ?? res.body;
      } catch (_) {
        // response wasn't JSON; fall back to raw body
      }
      throw ApiException(res.statusCode, message);
    }
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}
