import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/repositories/auth_repository.dart';

sealed class AuthState extends Equatable {
  const AuthState();
  @override
  List<Object?> get props => [];
}

/// Checking secure storage for a saved session before showing any auth UI.
class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthLoggedOut extends AuthState {
  const AuthLoggedOut();
}

class AuthSubmitting extends AuthState {
  const AuthSubmitting();
}

class AuthLoggedIn extends AuthState {
  final String wallet;
  const AuthLoggedIn(this.wallet);
  @override
  List<Object?> get props => [wallet];
}

class AuthError extends AuthState {
  final String message;
  const AuthError(this.message);
  @override
  List<Object?> get props => [message];
}

/// Drives registration/login for the app's built-in wallet. Connecting an external wallet
/// (WalletConnect) is a separate path -- see WalletCubit -- that this cubit doesn't manage, but
/// AccountGate (the app-root widget) treats either as "logged in".
class AuthCubit extends Cubit<AuthState> {
  final AuthRepository repository;
  AuthCubit(this.repository) : super(const AuthLoading()) {
    _tryResume();
  }

  Future<void> _tryResume() async {
    try {
      final wallet = await repository.tryResumeSession();
      emit(wallet != null ? AuthLoggedIn(wallet) : const AuthLoggedOut());
    } catch (_) {
      emit(const AuthLoggedOut());
    }
  }

  Future<void> register({required String username, required String email, required String password}) async {
    emit(const AuthSubmitting());
    try {
      final wallet = await repository.register(username: username, email: email, password: password);
      emit(AuthLoggedIn(wallet));
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> login({required String email, required String password}) async {
    emit(const AuthSubmitting());
    try {
      final wallet = await repository.login(email: email, password: password);
      emit(AuthLoggedIn(wallet));
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  /// Called after connecting an external wallet (WalletConnect) instead -- shares the same
  /// "logged in" state so AccountGate doesn't need to know which path was used.
  void useExternalWallet(String wallet) => emit(AuthLoggedIn(wallet));

  Future<void> logout() async {
    await repository.logout();
    emit(const AuthLoggedOut());
  }

  void backToLoggedOut() => emit(const AuthLoggedOut());
}
