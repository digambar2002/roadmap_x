import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:roadmap_x/core/models/models.dart';
import 'package:roadmap_x/features/dashboard/presentation/widgets/focus_goals_section.dart';
import 'package:roadmap_x/features/dashboard/providers/dashboard_provider.dart';

/// The point of goal priority is that a long list of goals stops reading as a
/// long list of obligations. These assert the dashboard actually holds that
/// line as the number of goals grows.
void main() {
  var nextId = 1;

  Goal makeGoal(String name, int priority) => Goal()
    ..id = nextId++
    ..uid = name
    ..name = name
    ..description = ''
    ..emoji = '🎯'
    ..colorHex = 0xFF4F46E5
    ..createdAt = DateTime(2026, 1, 1)
    ..targetDate = DateTime(2026, 12, 31)
    ..isArchived = false
    ..sortOrder = 0
    ..priority = priority
    ..updatedAt = DateTime(2026, 1, 1);

  DashboardData dataFor(List<Goal> goals) => DashboardData(
        overallPercent: 0.5,
        totalDone: 1,
        totalTasks: 2,
        goals: goals,
        goalProgress: {for (final g in goals) g.id: 0.5},
        goalProgressLabel: {for (final g in goals) g.id: 'Halfway'},
      );

  Future<void> pump(WidgetTester tester, List<Goal> goals) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => Scaffold(
            body: SingleChildScrollView(
              child: FocusGoalsSection(data: dataFor(goals)),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  setUp(() => nextId = 1);

  testWidgets('only Focus goals are listed when some are marked', (t) async {
    await pump(t, [
      makeGoal('Ship v1', GoalPriority.focus),
      makeGoal('Learn guitar', GoalPriority.active),
      makeGoal('Move house', GoalPriority.active),
      makeGoal('Someday trip', GoalPriority.someday),
    ]);

    expect(find.text('Focus'), findsOneWidget);
    expect(find.text('Ship v1'), findsOneWidget);
    expect(find.text('Learn guitar'), findsNothing);
    // The rest collapse to a count rather than filling the screen.
    expect(find.textContaining('3 more goals'), findsOneWidget);
    expect(find.textContaining('1 on Someday'), findsOneWidget);
  });

  testWidgets('falls back to a few active goals when none are Focus',
      (t) async {
    await pump(t, [
      for (var i = 1; i <= 6; i++) makeGoal('Goal $i', GoalPriority.active),
    ]);

    expect(find.text('Your goals'), findsOneWidget);
    // Capped at three, so six goals do not become a six-item wall.
    expect(find.text('Goal 1'), findsOneWidget);
    expect(find.text('Goal 3'), findsOneWidget);
    expect(find.text('Goal 4'), findsNothing);
    expect(find.textContaining('3 more goals'), findsOneWidget);
    expect(find.textContaining('Mark a goal as Focus'), findsOneWidget);
  });

  testWidgets('a single remaining goal is described in the singular',
      (t) async {
    await pump(t, [
      makeGoal('Ship v1', GoalPriority.focus),
      makeGoal('Other', GoalPriority.active),
    ]);

    expect(find.textContaining('1 more goal'), findsOneWidget);
    expect(find.textContaining('1 more goals'), findsNothing);
  });

  testWidgets('no goals renders nothing at all', (t) async {
    await pump(t, []);
    expect(find.text('Focus'), findsNothing);
    expect(find.text('Your goals'), findsNothing);
  });
}
