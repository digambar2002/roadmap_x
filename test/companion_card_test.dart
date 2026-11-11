import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:roadmap_x/core/gamification/gamification_service.dart';
import 'package:roadmap_x/core/gamification/progress_engine.dart';
import 'package:roadmap_x/core/services/shared_preferences_provider.dart';
import 'package:roadmap_x/features/companion/presentation/companion_card.dart';
import 'package:roadmap_x/features/companion/providers/companion_provider.dart';
import 'package:roadmap_x/features/pet/domain/pet_domain.dart';
import 'package:roadmap_x/features/pet/providers/pet_provider.dart';

GameState gameState({
  int habitsDue = 2,
  int habitsDone = 0,
  int tasksDone = 0,
  int openTasks = 1,
  int xp = 0,
}) =>
    GameState(
      openTasksToday: openTasks,
      snapshot: GameSnapshot(
        level: levelFor(xp),
        today: DayActivity(
          day: DateTime(2026, 11, 11),
          habitsDue: habitsDue,
          habitsDone: habitsDone,
          tasksDone: tasksDone,
        ),
        recentDays: const [],
      ),
    );

PetState pet({double food = 80, double water = 80}) => PetState(
      species: PetSpecies.cat,
      name: 'Mochi',
      needs: {
        PetNeed.food: food,
        PetNeed.water: water,
        PetNeed.fun: 80,
        PetNeed.clean: 80,
      },
      updatedAt: DateTime.now(),
      inventory: const {},
      coinsSpent: 0,
      bonusCoins: 0,
    );

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'level_seen': 1});
    prefs = await SharedPreferences.getInstance();
  });

  Future<void> pump(WidgetTester tester, GameState state, PetState? p,
      {int coins = 20}) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(
          body: CompanionCard(streak: 4, animate: false),
        ),
      ),
      GoRoute(
        path: '/pet',
        builder: (_, __) => const Scaffold(body: Text('pet tab')),
      ),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        gameStateProvider.overrideWith((ref) async => state),
        petViewProvider.overrideWithValue(p),
        coinBalanceProvider.overrideWithValue(coins),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
  }

  testWidgets('no pet yet: invites you to adopt one', (tester) async {
    await pump(tester, gameState(), null);
    expect(
        find.textContaining('Adopt a pet', findRichText: true), findsOneWidget);
  });

  testWidgets('a hungry pet says so and points to the Pet tab', (tester) async {
    await pump(tester, gameState(), pet(food: 10));
    expect(find.textContaining('Mochi is hungry'), findsOneWidget);
    expect(find.textContaining('Open the Pet tab'), findsOneWidget);
  });

  testWidgets('no coins: tells you how to earn them', (tester) async {
    await pump(tester, gameState(), pet(water: 5), coins: 0);
    expect(find.textContaining('Finish a task to earn coins'), findsOneWidget);
  });

  testWidgets('shows progress, coins and coins earned today', (tester) async {
    await pump(
        tester, gameState(habitsDone: 1, tasksDone: 2, openTasks: 1), pet());
    expect(find.text('3 of 5 done today'), findsOneWidget);
    expect(find.text('🪙 20'), findsOneWidget);
    // 1 habit (10 XP) + 2 tasks (30 XP) = 40 XP = 8 coins.
    expect(find.text('+8 today'), findsOneWidget);
    expect(find.text('🔥 4'), findsOneWidget);
  });

  testWidgets('a perfect day celebrates once', (tester) async {
    await pump(
        tester, gameState(habitsDone: 2, tasksDone: 1, openTasks: 0), pet());
    expect(find.textContaining('Perfect day!'), findsWidgets);
    expect(prefs.getString('perfect_day_celebrated'), isNotNull);
  });

  testWidgets('tapping opens the Pet tab', (tester) async {
    await pump(tester, gameState(habitsDone: 1), pet());
    await tester.tap(find.byType(CompanionCard));
    await tester.pumpAndSettle();
    expect(find.text('pet tab'), findsOneWidget);
  });
}
