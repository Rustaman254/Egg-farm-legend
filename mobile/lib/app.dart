import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'blocs/auth/auth_cubit.dart';
import 'blocs/wallet/wallet_cubit.dart';
import 'core/di/injector.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/home_shell.dart';
import 'presentation/widgets/account_gate.dart';

class EggFarmApp extends StatelessWidget {
  const EggFarmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthCubit>.value(value: getIt<AuthCubit>()),
        BlocProvider<WalletCubit>.value(value: getIt<WalletCubit>()),
      ],
      child: MaterialApp(
        title: 'EggFarm Legends',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: AccountGate(
          builder: (context, wallet) => HomeShell(wallet: wallet),
        ),
      ),
    );
  }
}
