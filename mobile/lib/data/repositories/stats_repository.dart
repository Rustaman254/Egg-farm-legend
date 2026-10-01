import '../../core/network/api_client.dart';
import '../models/activity.dart';
import '../models/dex_entry.dart';
import '../models/leaderboard_entry.dart';

/// Read-only wrapper for the three feature-parity screens that only ever read backend-cached
/// state (Species Dex, Leaderboard, Activity) -- unlike FarmRepository/MarketplaceRepository,
/// nothing here ever touches ContractService.
class StatsRepository {
  final ApiClient api;
  StatsRepository({required this.api});

  Future<List<DexEntry>> getDex(String wallet) async {
    final json = await api.getDex(wallet);
    return json.map((e) => DexEntry.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<TopBattler>> topBattlers() async {
    final json = await api.topBattlers();
    return json.map((e) => TopBattler.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<TopEarner>> topEarners() async {
    final json = await api.topEarners();
    return json.map((e) => TopEarner.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<PlayerActivity> getActivity(String wallet) async {
    final json = await api.activity(wallet);
    return PlayerActivity.fromJson(json);
  }
}
