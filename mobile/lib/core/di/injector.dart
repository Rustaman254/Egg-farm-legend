import 'package:get_it/get_it.dart';
import '../blockchain/contract_service.dart';
import '../blockchain/local_signer_service.dart';
import '../blockchain/transaction_signer.dart';
import '../blockchain/wallet_service.dart';
import '../network/api_client.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/battle_repository.dart';
import '../../data/repositories/farm_repository.dart';
import '../../data/repositories/marketplace_repository.dart';
import '../../data/repositories/stats_repository.dart';
import '../../data/repositories/task_repository.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../blocs/wallet/wallet_cubit.dart';

final getIt = GetIt.instance;

/// Wires up singletons once at app startup. Kept as a flat function (rather than modular
/// registration files) since the dependency graph is small enough to read at a glance.
void configureDependencies() {
  getIt.registerLazySingleton<ApiClient>(() => ApiClient());
  getIt.registerLazySingleton<WalletService>(() => WalletService());
  getIt.registerLazySingleton<LocalSignerService>(() => LocalSignerService());

  // ContractService signs through whichever wallet is active -- the built-in one by default
  // (see AuthRepository), or WalletConnect if the player chose "connect wallet instead".
  getIt.registerLazySingleton<ActiveSigner>(() => ActiveSigner());
  getIt.registerLazySingleton<ContractService>(() => ContractService(getIt<ActiveSigner>()));

  getIt.registerLazySingleton<FarmRepository>(
    () => FarmRepository(api: getIt<ApiClient>(), contracts: getIt<ContractService>()),
  );
  getIt.registerLazySingleton<TaskRepository>(() => TaskRepository(api: getIt<ApiClient>()));
  getIt.registerLazySingleton<MarketplaceRepository>(
    () => MarketplaceRepository(api: getIt<ApiClient>(), contracts: getIt<ContractService>()),
  );
  getIt.registerLazySingleton<BattleRepository>(() => BattleRepository(api: getIt<ApiClient>()));
  getIt.registerLazySingleton<StatsRepository>(() => StatsRepository(api: getIt<ApiClient>()));
  getIt.registerLazySingleton<AuthRepository>(
    () => AuthRepository(api: getIt<ApiClient>(), signer: getIt<LocalSignerService>(), activeSigner: getIt<ActiveSigner>()),
  );

  getIt.registerLazySingleton<WalletCubit>(() => WalletCubit(getIt<WalletService>()));
  getIt.registerLazySingleton<AuthCubit>(() => AuthCubit(getIt<AuthRepository>()));
}
