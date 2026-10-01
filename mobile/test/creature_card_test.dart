import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:eggfarm_legends/blocs/battle/battle_cubit.dart';
import 'package:eggfarm_legends/data/models/creature.dart';
import 'package:eggfarm_legends/presentation/widgets/creature_card.dart';

class MockBattleCubit extends MockCubit<BattleState> implements BattleCubit {}

void main() {
  // CreatureCard reads the ability catalog off BattleCubit (see AbilityBadges) -- every test
  // wraps it in a mock with an empty catalog so that read doesn't need a real cubit/repository.
  Widget wrap(Widget child) {
    final cubit = MockBattleCubit();
    when(() => cubit.state).thenReturn(const BattleState());
    when(() => cubit.stream).thenAnswer((_) => const Stream.empty());
    return MaterialApp(
      home: BlocProvider<BattleCubit>.value(value: cubit, child: Scaffold(body: child)),
    );
  }

  Creature buildCreature({int hunger = 80, int happiness = 60, DateTime? lastEggAt}) {
    return Creature(
      tokenId: 1,
      ownerAddress: '0xabc',
      species: 0,
      rarity: 1,
      breedCount: 0,
      happiness: happiness,
      hunger: hunger,
      birthTime: DateTime.now(),
      lastFedAt: DateTime.now(),
      lastEggAt: lastEggAt,
    );
  }

  testWidgets('CreatureCard shows species name, hunger, and happiness', (tester) async {
    final creature = buildCreature(hunger: 70, happiness: 55);

    await tester.pumpWidget(wrap(CreatureCard(creature: creature)));

    expect(find.text('Chicken'), findsOneWidget);
    expect(find.text('70%'), findsOneWidget);
    expect(find.text('55%'), findsOneWidget);
  });

  testWidgets('Feed button triggers onFeed callback', (tester) async {
    var fed = false;
    final creature = buildCreature();

    await tester.pumpWidget(wrap(CreatureCard(creature: creature, onFeed: () => fed = true)));

    await tester.tap(find.text('Feed'));
    await tester.pump();

    expect(fed, isTrue);
  });

  testWidgets('Egg button is disabled during cooldown', (tester) async {
    final creature = buildCreature(lastEggAt: DateTime.now());
    var collected = false;

    await tester.pumpWidget(wrap(CreatureCard(creature: creature, onCollectEgg: () => collected = true)));

    // A cooldown label (e.g. "2h"/"1h") should render instead of "Egg".
    expect(find.text('Egg'), findsNothing);

    final eggButton = tester.widgetList<ElevatedButton>(find.byType(ElevatedButton)).last;
    expect(eggButton.onPressed, isNull);
    expect(collected, isFalse);
  });
}
