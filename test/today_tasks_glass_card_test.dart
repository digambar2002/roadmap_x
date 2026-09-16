import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:roadmap_x/core/models/models.dart';
import 'package:roadmap_x/core/models/today_task.dart';
import 'package:roadmap_x/features/tasks/providers/task_provider.dart';
import 'package:roadmap_x/features/today/presentation/widgets/today_tasks_glass_card.dart';

void main() {
  testWidgets('renders empty state when no tasks are due', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todayTasksGroupedProvider.overrideWith(
            (ref) => Future.value(
              const TodayTasksData(
                overdue: [],
                dueToday: [],
                thisWeek: [],
                noDueDate: [],
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: TodayTasksGlassCard(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text("Today's Tasks"), findsOneWidget);
    expect(find.text('All caught up!'), findsOneWidget);
    expect(find.text('No tasks due today.'), findsOneWidget);
    expect(find.text('All Clear ✨'), findsOneWidget);
  });

  testWidgets('renders tasks with glassmorphism badges and goal names', (tester) async {
    final task1 = Task()
      ..uid = 't1'
      ..text = 'Finish Flutter Widget'
      ..isCompleted = false
      ..dueDate = DateTime.now()
      ..priority = 1
      ..createdAt = DateTime.now()
      ..sortOrder = 0
      ..milestoneUid = 'm1'
      ..updatedAt = DateTime.now();

    final goal1 = Goal()
      ..uid = 'g1'
      ..name = 'Mobile App'
      ..description = ''
      ..emoji = '📱'
      ..colorHex = 0xFF4F46E5
      ..createdAt = DateTime.now()
      ..targetDate = DateTime.now()
      ..isArchived = false
      ..sortOrder = 0
      ..priority = 2
      ..updatedAt = DateTime.now();

    final taskCtx = TodayTaskContext(
      task: task1,
      goal: goal1,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todayTasksGroupedProvider.overrideWith(
            (ref) => Future.value(
              TodayTasksData(
                overdue: [],
                dueToday: [taskCtx],
                thisWeek: [],
                noDueDate: [],
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: TodayTasksGlassCard(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text("Today's Tasks"), findsOneWidget);
    expect(find.text('Finish Flutter Widget'), findsOneWidget);
    expect(find.text('Mobile App'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('1 task'), findsOneWidget);
  });
}
