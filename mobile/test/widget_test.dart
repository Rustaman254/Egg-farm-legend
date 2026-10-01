import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:eggfarm_legends/blocs/auth/auth_cubit.dart';
import 'package:eggfarm_legends/presentation/widgets/account_gate.dart';

class MockAuthCubit extends MockCubit<AuthState> implements AuthCubit {}

void main() {
  testWidgets('AccountGate shows the auth screen when logged out', (tester) async {
    final cubit = MockAuthCubit();
    when(() => cubit.state).thenReturn(const AuthLoggedOut());
    when(() => cubit.stream).thenAnswer((_) => const Stream.empty());

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<AuthCubit>.value(
          value: cubit,
          child: AccountGate(
            builder: (context, wallet) => Text('Logged in as $wallet'),
          ),
        ),
      ),
    );

    expect(find.text('EggFarm Legends'), findsOneWidget);
    expect(find.text('Create Account'), findsOneWidget);
    expect(find.textContaining('Logged in as'), findsNothing);
  });

  testWidgets('AccountGate renders the gated content once logged in', (tester) async {
    final cubit = MockAuthCubit();
    when(() => cubit.state).thenReturn(const AuthLoggedIn('0xABC123'));
    when(() => cubit.stream).thenAnswer((_) => const Stream.empty());

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<AuthCubit>.value(
          value: cubit,
          child: AccountGate(
            builder: (context, wallet) => Text('Logged in as $wallet'),
          ),
        ),
      ),
    );

    expect(find.text('Logged in as 0xABC123'), findsOneWidget);
    expect(find.text('Create Account'), findsNothing);
  });
}
