import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../blocs/wallet/wallet_cubit.dart';
import '../../core/theme/app_theme.dart';

/// The app's front door: register or log in with the built-in wallet (the default, no external
/// app needed), or connect an existing wallet instead (WalletConnect -- the same flow the webapp
/// uses). Either path lands in AccountGate's "logged in" state.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

enum _Mode { register, login, connectWallet }

class _AuthScreenState extends State<AuthScreen> {
  _Mode _mode = _Mode.register;
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.asset('assets/logo.png', height: 120, width: 120),
                    const SizedBox(height: 12),
                    const Text(
                      'EggFarm Legends',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Breed, feed, and battle creatures on Arbitrum',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 32),
                    if (_mode == _Mode.connectWallet) const _ConnectWalletPanel() else _buildAuthForm(),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: () => setState(() => _mode = _mode == _Mode.connectWallet ? _Mode.register : _Mode.connectWallet),
                      child: Text(
                        _mode == _Mode.connectWallet ? 'Use a username instead' : 'Or connect your own wallet',
                        style: const TextStyle(color: AppColors.textFaint),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthForm() {
    return BlocConsumer<AuthCubit, AuthState>(
      listenWhen: (prev, curr) => curr is AuthError,
      listener: (context, state) {
        if (state is AuthError) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message), backgroundColor: AppColors.danger));
        }
      },
      builder: (context, state) {
        final submitting = state is AuthSubmitting;
        final isRegister = _mode == _Mode.register;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // No wallet needed -- registering/logging in creates or recovers your wallet
            // automatically; there's nothing else to connect.
            Container(
              decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(child: _ModeTab(label: 'Sign Up', selected: isRegister, onTap: () => setState(() => _mode = _Mode.register))),
                  Expanded(child: _ModeTab(label: 'Log In', selected: !isRegister, onTap: () => setState(() => _mode = _Mode.login))),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (isRegister) ...[
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: isRegister ? 'This also protects your wallet backup -- don\'t lose it.' : null,
                helperMaxLines: 2,
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: AppColors.textFaint),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: submitting ? null : () => _submit(context, isRegister),
              child: submitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(isRegister ? 'Create Account' : 'Log In'),
            ),
            if (isRegister) ...[
              const SizedBox(height: 10),
              const Text(
                'A wallet is created for you automatically -- no separate app needed.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppColors.textFaint),
              ),
            ],
          ],
        );
      },
    );
  }

  void _submit(BuildContext context, bool isRegister) {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (isRegister) {
      final username = _usernameController.text.trim();
      context.read<AuthCubit>().register(username: username, email: email, password: password);
    } else {
      context.read<AuthCubit>().login(email: email, password: password);
    }
  }
}

class _ModeTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeTab({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(fontWeight: FontWeight.bold, color: selected ? Colors.white : AppColors.textFaint),
        ),
      ),
    );
  }
}

/// The webapp-style path: pair with an external wallet app over WalletConnect. Kept as a
/// secondary option on mobile -- the built-in wallet (see AuthCubit) is the default.
class _ConnectWalletPanel extends StatelessWidget {
  const _ConnectWalletPanel();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<WalletCubit, WalletState>(
      listener: (context, state) {
        if (state is WalletConnected) {
          context.read<AuthCubit>().useExternalWallet(state.address);
        }
      },
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state is WalletConnecting) ...[
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                state.pairingUri != null ? 'Approve the connection in your wallet app' : 'Opening wallet...',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ] else ...[
              if (state is WalletError)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(state.message, style: const TextStyle(color: AppColors.danger, fontSize: 12), textAlign: TextAlign.center),
                ),
              ElevatedButton.icon(
                onPressed: () => context.read<WalletCubit>().connect(),
                icon: const Icon(Icons.account_balance_wallet),
                label: const Text('Connect Wallet'),
              ),
            ],
          ],
        );
      },
    );
  }
}
