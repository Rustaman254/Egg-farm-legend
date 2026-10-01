import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/models/dex_entry.dart';
import '../../data/repositories/stats_repository.dart';

abstract class DexState extends Equatable {
  const DexState();
  @override
  List<Object?> get props => [];
}

class DexInitial extends DexState {
  const DexInitial();
}

class DexLoading extends DexState {
  const DexLoading();
}

class DexLoaded extends DexState {
  final List<DexEntry> entries;
  const DexLoaded(this.entries);
  @override
  List<Object?> get props => [entries];
}

class DexError extends DexState {
  final String message;
  const DexError(this.message);
  @override
  List<Object?> get props => [message];
}

class DexCubit extends Cubit<DexState> {
  final StatsRepository repository;
  DexCubit(this.repository) : super(const DexInitial());

  Future<void> load(String wallet) async {
    emit(const DexLoading());
    try {
      final entries = await repository.getDex(wallet);
      emit(DexLoaded(entries));
    } catch (e) {
      emit(DexError(e.toString()));
    }
  }
}
