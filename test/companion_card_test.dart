import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:roadmap_x/core/gamification/gamification_service.dart';
import 'package:roadmap_x/core/gamification/progress_engine.dart';
import 'package:roadmap_x/core/services/shared_preferences_provider.dart';
import 'package:roadmap_x/features/companion/presentation/companion_card.dart';
import 'package:roadmap_x/features/companion/providers/companion_provider.dart';

GameState gameState({
  int habitsDue = 2,
  int habitsDone = 0,
  int tasksDone = 0,
  int openTasks = 1,
  int health = 80,
  CompanionKind kind = CompanionKind.plant,
  int xp = 0,
}) =>
    GameState(
      openTasksToday: openTasks,
      snapshot: GameSnapshot(
        kind: kind,
        name: kind == CompanionKind.plant ? 'Sprout' : 'Mochi',
        level: levelFor(xp),
        health: health,
        today: DayActivity(
          day: DateTime(2026, 11, 11),
          habitsDue: habitsDue,
          habitsDone: habitsDone,
          tasksDone: tasksDone,
        ),
        recentDays: [
          for (var i = 7; i >= 1; i--)
            DayActivity(
              day: DateTime(2026, 11, 11 - i),
              habitsDue: 1,
              habitsDone: i.isEven ? 1 : 0,
              tasksDone: 0,
            ),
        ],
      ),
    );

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'level_seen': 1});
    prefs = await SharedPreferences.getInstance();
  });

  Future<void> pump(WidgetTester tester, GameState state) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        gameStateProvider.overrideWith((ref) async => state),
      ],
      child: const MaterialApp(
        home: Scaffold(body: CompanionCard(streak: 4)),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
  }

  testWidgets('nothing done yet: hungry warning', (tester) async {
    await pump(tester, gameState());
    expect(find.textContaining('Sprout is hungry'), findsOneWidget);
    expect(find.text('🌱'), findsOneWidget);
  });

  testWidgets('nothing planned at all: bored, plan something', (tester) async {
    await pump(tester, gameState(habitsDue: 0, openTasks: 0));
    expect(find.textContaining('Plan something'), findsOneWidget);
  });

  testWidgets('progress shows how much of today is done and what was earned',
      (tester) async {
    await pump(tester, gameState(habitsDone: 1, tasksDone: 2, openTasks: 1));
    expect(find.text('3 of 5 done today'), findsOneWidget);
    expect(find.text('💧 1'), findsOneWidget);
    expect(find.text('🍎 2'), findsOneWidget);
    expect(find.text('🔥 4'), findsOneWidget);
  });

  testWidgets('a perfect day celebrates once', (tester) async {
    await pump(tester,
        gameState(habitsDone: 2, tasksDone: 1, openTasks: 0));
    expect(find.textContaining('Perfect day!'), findsWidgets);
    expect(find.text('⭐ 1'), findsOneWidget);
    expect(prefs.getString('perfect_day_celebrated'), isNotNull);
  });

  testWidgets('pet shows a mood face; low health looks unwell',
      (tester) async {
    await pump(tester, gameState(kind: CompanionKind.pet, health: 5));
    expect(find.text('🙀'), findsOneWidget);
    expect(find.textContaining('Unwell'), findsOneWidget);
  });

  testWidgets('tapping opens the companion sheet with how it works',
      (tester) async {
    await pump(tester, gameState(habitsDone: 1));
    await tester.tap(find.byType(CompanionCard));
    // The companion bobs in a loop, so step time instead of settling.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('HOW IT WORKS'), findsOneWidget);
    expect(find.text('Plant'), findsOneWidget);
    expect(find.text('Pet'), findsOneWidget);
  });
}
