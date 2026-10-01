import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/blockchain/wallet_service.dart';

sealed class WalletState {
  const WalletState();
}

class WalletDisconnected extends WalletState {
  const WalletDisconnected();
}

class WalletConnecting extends WalletState {
  final String? pairingUri;
  const WalletConnecting({this.pairingUri});
}

class WalletConnected extends WalletState {
  final String address;
  const WalletConnected(this.address);
}

class WalletError extends WalletState {
  final String message;
  const WalletError(this.message);
}

class WalletCubit extends Cubit<WalletState> {
  final WalletService service;
  WalletCubit(this.service) : super(const WalletDisconnected());

  Future<void> connect() async {
    emit(const WalletConnecting());
    try {
      final address = await service.connect(
        onPairingUri: (uri) => emit(WalletConnecting(pairingUri: uri)),
      );
      emit(WalletConnected(address));
    } catch (e) {
      emit(WalletError(e.toString()));
    }
  }

  Future<void> disconnect() async {
    await service.disconnect();
    emit(const WalletDisconnected());
  }

  String? get currentAddress => state is WalletConnected ? (state as WalletConnected).address : null;
}
