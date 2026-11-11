import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:roadmap_x/core/gamification/gamification_service.dart';
import 'package:roadmap_x/features/pet/providers/pet_provider.dart';
import 'package:roadmap_x/core/gamification/progress_engine.dart';
import 'package:roadmap_x/core/models/models.dart';
import 'package:roadmap_x/features/companion/presentation/companion_card.dart';
import 'package:roadmap_x/features/companion/providers/companion_provider.dart';
import 'package:roadmap_x/core/services/shared_preferences_provider.dart';
import 'package:roadmap_x/core/theme/app_theme.dart';
import 'package:roadmap_x/features/ai_coach/presentation/daily_briefing_card.dart';
import 'package:roadmap_x/features/ai_coach/providers/ai_coach_provider.dart';
import 'package:roadmap_x/features/dashboard/presentation/widgets/daily_habits_section.dart';
import 'package:roadmap_x/features/dashboard/presentation/dashboard_screen.dart';
import 'package:roadmap_x/features/dashboard/presentation/widgets/collapsible_briefing.dart';
import 'package:roadmap_x/core/layout/breakpoints.dart';
import 'package:roadmap_x/features/dashboard/providers/dashboard_provider.dart';
import 'package:roadmap_x/features/schedule/providers/schedule_provider.dart';
import 'package:roadmap_x/features/habits/providers/habit_provider.dart';
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
      );
}

class _FakeHabits extends TodayHabitChecksNotifier {
  @override
  Future<Set<String>> build() async => {'h1'};
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

  ScheduleItem makeScheduleItem() => ScheduleItem()
    ..id = 1
    ..uid = 's1'
    ..label = 'Deep work'
    ..detail = ''
    ..time = '9:00 AM'
    ..weekdays = [0, 1, 2, 3, 4, 5, 6]
    ..goalUid = ''
    ..isActive = true
    ..sortOrder = 0
    ..updatedAt = DateTime(2026, 1, 1);

  Future<void> pumpDashboard(
    WidgetTester tester, {
    required List<Goal> goals,
    Size window = const Size(430, 932),
    bool hasAi = true,
    List<ScheduleItem> schedule = const [],
  }) async {
    tester.view.physicalSize = window;
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
        for (final p in ['/tasks', '/analytics', '/goals', '/schedule'])
          GoRoute(path: p, builder: (_, __) => const SizedBox.shrink()),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          settingsProvider.overrideWith(_FakeSettings.new),
          todayHabitChecksProvider.overrideWith(_FakeHabits.new),
          habitsProvider.overrideWith((ref) => Stream.value(<Habit>[])),
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
          // No pet adopted, so no looping pet animation to block
          // pumpAndSettle.
          petViewProvider.overrideWithValue(null),
          coinBalanceProvider.overrideWithValue(12),
          gameStateProvider.overrideWith((ref) async => GameState(
                openTasksToday: 0,
                snapshot: GameSnapshot(
                  level: levelFor(450),
                  today: DayActivity(
                    day: DateTime(2026, 11, 11),
                    habitsDue: 0,
                    habitsDone: 0,
                    tasksDone: 0,
                  ),
                  recentDays: const [],
                ),
              )),
          hasAiCoachProvider.overrideWithValue(hasAi),
          scheduleForWeekdayProvider
              .overrideWith((ref, weekday) => Stream.value(schedule)),
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

  testWidgets('renders the day instead of a blank page', (tester) async {
    await pumpDashboard(tester, goals: [
      makeGoal(1, 'Ship v1', GoalPriority.focus),
      makeGoal(2, 'Learn guitar', GoalPriority.active),
    ]);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Digambar'), findsOneWidget, reason: 'greeting');
    expect(find.byType(CompanionCard), findsOneWidget,
        reason: 'the companion leads the page');
    expect(find.textContaining('Adopt a pet', findRichText: true), findsOneWidget);
    expect(find.text('🪙 12'), findsOneWidget);
    expect(find.text('Lv 3'), findsOneWidget);
    expect(find.text('🔥 7'), findsOneWidget, reason: 'streak on the card');
    expect(find.text("Today's tasks"), findsOneWidget);
    expect(find.byType(DailyHabitsSection), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget,
        reason: 'one entry point for creating things');
  });

  testWidgets('long-term goals live on the Goals tab, not here',
      (tester) async {
    await pumpDashboard(tester, goals: [makeGoal(1, 'Ship v1', GoalPriority.focus)]);
    expect(find.text('Ship v1'), findsNothing);
  });

  testWidgets('the collapsed briefing does not build the AI card',
      (tester) async {
    await pumpDashboard(tester, goals: [makeGoal(1, 'Ship v1', GoalPriority.focus)]);
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('Daily briefing'), findsOneWidget);
    expect(find.byType(DailyBriefingCard), findsNothing);
  });

  testWidgets('no AI coach configured means no briefing card', (tester) async {
    await pumpDashboard(tester, goals: [makeGoal(1, 'Ship v1', GoalPriority.focus)], hasAi: false);
    expect(find.byType(CollapsibleBriefing), findsNothing);
  });

  testWidgets('a brand-new install gets one clear next step', (tester) async {
    await pumpDashboard(tester, goals: []);
    expect(tester.takeException(), isNull);
    expect(find.text('Start your roadmap'), findsOneWidget);
    expect(find.text('Create a goal'), findsOneWidget);
  });

  testWidgets('the "+" button offers everything that can be created',
      (tester) async {
    await pumpDashboard(tester, goals: [makeGoal(1, 'Ship v1', GoalPriority.focus)]);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    for (final label in [
      'Tasks for today',
      'Habit',
      'Goal',
      'Goal with AI',
      'Goal from text',
      'Routine',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('reflows into two columns on a desktop window', (tester) async {
    await pumpDashboard(
      tester,
      goals: [makeGoal(1, 'Ship v1', GoalPriority.focus)],
      window: const Size(1600, 1000),
      schedule: [makeScheduleItem()],
    );

    expect(tester.takeException(), isNull);

    final tasks = tester.getTopLeft(find.text("Today's tasks"));
    final schedule = tester.getTopLeft(find.text("Today's schedule"));
    expect(schedule.dx, greaterThan(tasks.dx),
        reason: 'the secondary column sits beside the main one');

    final listWidth = tester.getSize(find.byType(ListView)).width;
    expect(listWidth, lessThanOrEqualTo(Breakpoints.wideMaxWidth));
    expect(tester.getTopLeft(find.byType(ListView)).dx, greaterThan(0));
    // Let the staggered entrance animations finish before teardown.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets("today's tasks sit above the schedule on a phone",
      (tester) async {
    await pumpDashboard(
      tester,
      goals: [makeGoal(1, 'Ship v1', GoalPriority.focus)],
      schedule: [makeScheduleItem()],
    );

    expect(tester.takeException(), isNull);
    final tasks = tester.getTopLeft(find.text("Today's tasks"));
    await tester.dragUntilVisible(
      find.text("Today's schedule"),
      find.byType(ListView),
      const Offset(0, -200),
    );
    final schedule = tester.getTopLeft(find.text("Today's schedule"));
    expect(tasks.dx, schedule.dx, reason: 'single column');
    expect(tasks.dy, lessThan(schedule.dy));
    await tester.pumpAndSettle();
  });

  testWidgets('habits on Today have no calendar; that lives on the Habits tab',
      (tester) async {
    await pumpDashboard(tester, goals: [makeGoal(1, 'Ship v1', GoalPriority.focus)]);
    expect(find.text('Habits'), findsOneWidget);
    expect(find.text('Mon'), findsNothing);
  });

  testWidgets('an empty schedule takes no space', (tester) async {
    await pumpDashboard(tester, goals: [makeGoal(1, 'Ship v1', GoalPriority.focus)]);
    expect(find.text("Today's schedule"), findsNothing);
  });

  testWidgets('an empty task list still says so rather than vanishing',
      (tester) async {
    await pumpDashboard(tester, goals: [makeGoal(1, 'Ship v1', GoalPriority.focus)]);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Nothing due'), findsOneWidget);
  });
}
