import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../core/theme/app_theme.dart';
import '../screens/auth_screen.dart';

/// Gates the whole app behind having *a* wallet -- the built-in one by default (register/log in,
/// no external app needed) or a connected external wallet if the player chose that on the auth
/// screen instead. Replaces the old wallet-only ConnectWalletGate.
class AccountGate extends StatelessWidget {
  final Widget Function(BuildContext context, String wallet) builder;

  const AccountGate({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, state) {
        return switch (state) {
          AuthLoggedIn(:final wallet) => builder(context, wallet),
          AuthLoading() => const Scaffold(
              backgroundColor: AppColors.background,
              body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
            ),
          _ => const AuthScreen(),
        };
      },
    );
  }
}
