import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:roadmap_x/core/models/models.dart';
import 'package:roadmap_x/core/services/shared_preferences_provider.dart';
import 'package:roadmap_x/core/theme/app_theme.dart';
import 'package:roadmap_x/features/dashboard/presentation/dashboard_screen.dart';
import 'package:roadmap_x/features/dashboard/providers/dashboard_provider.dart';
import 'package:roadmap_x/features/schedule/providers/schedule_provider.dart';
import 'package:roadmap_x/features/settings/providers/habit_checkin_provider.dart';
import 'package:roadmap_x/features/settings/providers/settings_provider.dart';
import 'package:roadmap_x/features/tasks/providers/task_provider.dart';

/// Pumps the real DashboardScreen. The widget-level tests cover the individual
/// sections; this one exists to catch the failure they cannot — the whole page
/// coming up blank.
class _FakeSettings extends SettingsNotifier {
  @override
  Future<SettingsState> build() async => const SettingsState(
        userName: 'Digambar',
        themeMode: 'dark',
        dailyReminderEnabled: false,
        dailyReminderHour: 9,
        dailyReminderMinute: 0,
        taskDueNotificationsEnabled: true,
        nonNegotiables: ['Workout', 'Deep work', 'Read', 'Review'],
      );
}

class _FakeHabits extends TodayHabitChecksNotifier {
  @override
  Future<List<bool>> build() async => [true, false, false, false];
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Goal makeGoal(int id, String name, int priority) => Goal()
    ..id = id
    ..uid = 'g$id'
    ..name = name
    ..description = ''
    ..emoji = '🎯'
    ..colorHex = 0xFF4F46E5
    ..createdAt = DateTime(2026, 1, 1)
    ..targetDate = DateTime(2026, 12, 31)
    ..isArchived = false
    ..sortOrder = id
    ..priority = priority
    ..updatedAt = DateTime(2026, 1, 1);

  Future<void> pumpDashboard(
    WidgetTester tester, {
    required List<Goal> goals,
  }) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final data = DashboardData(
      overallPercent: 0.42,
      totalDone: 21,
      totalTasks: 50,
      goals: goals,
      goalProgress: {for (final g in goals) g.id: 0.5},
      goalProgressLabel: {for (final g in goals) g.id: 'Halfway'},
    );

    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const DashboardScreen()),
        for (final p in ['/today', '/analytics', '/goals', '/schedule'])
          GoRoute(path: p, builder: (_, __) => const SizedBox.shrink()),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          settingsProvider.overrideWith(_FakeSettings.new),
          todayHabitChecksProvider.overrideWith(_FakeHabits.new),
          dashboardDataProvider.overrideWithValue(AsyncData(data)),
          todayTasksGroupedProvider.overrideWith(
            (ref) async => const TodayTasksData(
              overdue: [],
              dueToday: [],
              thisWeek: [],
              noDueDate: [],
            ),
          ),
          habitStreakProvider.overrideWith((ref) async => 7),
          scheduleForWeekdayProvider
              .overrideWith((ref, weekday) => Stream.value(<ScheduleItem>[])),
          scheduleCompletedUidsProvider
              .overrideWith((ref, date) async => <String>{}),
        ],
        child: MaterialApp.router(
          theme: AppTheme.dark,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders its sections instead of a blank page', (tester) async {
    await pumpDashboard(tester, goals: [
      makeGoal(1, 'Ship v1', GoalPriority.focus),
      makeGoal(2, 'Learn guitar', GoalPriority.active),
    ]);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Digambar'), findsOneWidget, reason: 'greeting');
    expect(find.text('Overdue'), findsOneWidget, reason: 'stat strip');
    expect(find.text('42%'), findsOneWidget, reason: 'progress stat');
    expect(find.text('7'), findsOneWidget, reason: 'streak stat');
    expect(find.text('Ship v1'), findsOneWidget, reason: 'focus goal');

    // The briefing is deliberately last and starts closed, so it is below the
    // fold and not built until scrolled to — which is the whole point of
    // moving it off the first screen.
    expect(find.text('Daily briefing'), findsNothing,
        reason: 'briefing should not occupy the first screen');

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('Daily briefing'), findsOneWidget,
        reason: 'briefing row is reachable by scrolling');
  });

  testWidgets('renders with no goals at all', (tester) async {
    await pumpDashboard(tester, goals: []);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Digambar'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('No goals yet'), findsOneWidget);
  });
}
