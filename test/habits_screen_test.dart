import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:roadmap_x/core/models/models.dart';
import 'package:roadmap_x/core/services/habit_customization_service.dart';
import 'package:roadmap_x/core/services/shared_preferences_provider.dart';
import 'package:roadmap_x/core/theme/app_theme.dart';
import 'package:roadmap_x/features/habits/presentation/habits_screen.dart';
import 'package:roadmap_x/features/habits/presentation/widgets/habit_month_calendar.dart';
import 'package:roadmap_x/features/habits/providers/habit_provider.dart';

class _Checks extends TodayHabitChecksNotifier {
  @override
  Future<Set<String>> build() async => {};
}

void main() {
  testWidgets('a new Night habit shows under Night, empty sections hide',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final habits = StreamController<List<Habit>>();

    Habit h(String uid, String label) => Habit()
      ..id = uid.hashCode
      ..uid = uid
      ..label = label
      ..iconKey = 'gym'
      ..sortOrder = 0
      ..createdAt = DateTime(2026, 1, 1)
      ..updatedAt = DateTime(2026, 1, 1);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        habitsProvider.overrideWith((ref) => habits.stream),
        todayHabitChecksProvider.overrideWith(_Checks.new),
        habitStreakProvider.overrideWith((ref) async => 0),
        habitWeeklyProgressProvider.overrideWith((ref) async => {}),
        habitCompletedDaysInWeekProvider.overrideWith((ref, d) async => {}),
        habitChecksForDateProvider.overrideWith((ref, d) async => {}),
        habitCheckedDatesProvider.overrideWith((ref, uid) async => {}),
      ],
      child: MaterialApp(theme: AppTheme.dark, home: const HabitsScreen()),
    ));
    habits.add([h('a', 'Existing')]);
    await tester.pumpAndSettle();

    // Real order: the row is written (stream emits) before its category is.
    habits.add([h('a', 'Existing'), h('b', 'Night walk')]);
    await tester.pump();
    await prefs.setString('habit_meta_b',
        jsonEncode(const HabitCustomization(category: 'Night').toJson()));
    final container = ProviderScope.containerOf(
        tester.element(find.byType(HabitsScreen)));
    container.read(habitCustomizationVersionProvider.notifier).state++;
    await tester.pumpAndSettle();

    // The new habit lands under its own time of day…
    final night = tester.getTopLeft(find.text('NIGHT')).dy;
    final walk = tester.getTopLeft(find.text('Night walk').last).dy;
    expect(walk, greaterThan(night));

    // …and sections with no habits are not shown at all.
    expect(find.text('MORNING'), findsOneWidget);
    expect(find.text('WORKLOAD'), findsNothing);
    expect(find.text('ANYTIME'), findsNothing);
    await habits.close();
  });

  testWidgets('Analytics tab lists habits and opens a month calendar',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);

    final habit = Habit()
      ..id = 1
      ..uid = 'r'
      ..label = 'Read'
      ..iconKey = 'read'
      ..sortOrder = 0
      ..createdAt = DateTime(now.year - 2, 1, 1)
      ..updatedAt = DateTime(2026, 1, 1);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        habitsProvider.overrideWith((ref) => Stream.value([habit])),
        todayHabitChecksProvider.overrideWith(_Checks.new),
        habitStreakProvider.overrideWith((ref) async => 0),
        habitWeeklyProgressProvider.overrideWith((ref) async => {}),
        habitCompletedDaysInWeekProvider.overrideWith((ref, d) async => {}),
        habitChecksForDateProvider.overrideWith((ref, d) async => {}),
        habitCheckedDatesProvider
            .overrideWith((ref, uid) async => {today, yesterday}),
      ],
      child: MaterialApp(theme: AppTheme.dark, home: const HabitsScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Top Habits (This Week)'), findsNothing,
        reason: 'the weekly card was removed');

    await tester.tap(find.text('Analytics'));
    await tester.pumpAndSettle();
    expect(find.text('Read'), findsOneWidget);
    expect(find.textContaining('2 day streak'), findsOneWidget);

    await tester.tap(find.text('Read'));
    await tester.pumpAndSettle();
    expect(find.byType(HabitMonthGrid), findsOneWidget);

    // Months and years page freely in both directions.
    final monthLabel = DateFormat('MMMM yyyy').format(today);
    String label(int y, int m) => DateFormat('MMMM yyyy').format(DateTime(y, m));
    expect(find.text(monthLabel), findsOneWidget);
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text(label(today.year, today.month - 1)), findsOneWidget);
    await tester.tap(find.byTooltip('Previous year'));
    await tester.pumpAndSettle();
    expect(find.text(label(today.year - 1, today.month - 1)), findsOneWidget);
    await tester.tap(find.byTooltip('Next year'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(find.text(monthLabel), findsOneWidget);
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(find.text(label(today.year, today.month + 1)), findsOneWidget,
        reason: 'future months open too, shown faded');
    await tester.tap(find.textContaining('Back to this month'));
    await tester.pumpAndSettle();
    expect(find.text(monthLabel), findsOneWidget);
  });

  group('HabitStats', () {
    final now = DateTime(2026, 11, 11); // a Wednesday
    DateTime d(int day) => DateTime(2026, 11, day);

    test('an unticked today does not break the streak', () {
      final s = HabitStats.from({d(9), d(10)}, const HabitCustomization(),
          now: now);
      expect(s.currentStreak, 2);
      expect(s.thisMonth, 2);
    });

    test('weekdays-only habits are not broken by the weekend', () {
      const weekdays = HabitCustomization(repeatDays: [1, 2, 3, 4, 5]);
      // Fri 6, Mon 9, Tue 10, Wed 11.
      final s = HabitStats.from({d(6), d(9), d(10), d(11)}, weekdays, now: now);
      expect(s.currentStreak, 4);
      expect(s.bestStreak, 4);
    });

    test('a missed day ends the streak but keeps the best', () {
      final s = HabitStats.from({d(1), d(2), d(3), d(10), d(11)},
          const HabitCustomization(), now: now);
      expect(s.currentStreak, 2);
      expect(s.bestStreak, 3);
      expect(s.total, 5);
    });
  });
}
