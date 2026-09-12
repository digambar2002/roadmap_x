import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:roadmap_x/core/db/isar_service.dart';
import 'package:roadmap_x/core/models/models.dart';
import 'package:roadmap_x/core/models/today_task.dart';
import 'package:roadmap_x/core/theme/app_theme.dart';
import 'package:roadmap_x/features/goals/data/goal_repository.dart';
import 'package:roadmap_x/features/goals/providers/goal_provider.dart';
import 'package:roadmap_x/features/milestones/data/milestone_repository.dart';
import 'package:roadmap_x/features/tasks/data/task_repository.dart';
import 'package:roadmap_x/features/tasks/providers/task_provider.dart';
import 'package:roadmap_x/features/today/presentation/today_screen.dart';
import 'package:roadmap_x/features/today/presentation/widgets/pick_goal_tasks_sheet.dart';
import 'package:roadmap_x/features/today/providers/today_provider.dart';

void main() {
  late Directory dir;
  late Isar isar;

  setUpAll(() async => Isar.initializeIsarCore(download: true));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('roadmapx_tasks_test');
    isar = await Isar.open(
      [
        GoalSchema,
        MilestoneSchema,
        TaskSchema,
        ScheduleItemSchema,
        HabitSchema,
        HabitCheckinSchema,
        ScheduleCompletionSchema,
        AppSettingSchema,
      ],
      directory: dir.path,
      name: 'tasks_${dir.path.hashCode}',
    );
    IsarService.instance.overrideForTesting(isar);
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  final goalRepo = GoalRepository.instance;
  final milestoneRepo = MilestoneRepository.instance;
  final taskRepo = TaskRepository.instance;

  test('setDueDates and setDueDate update task due dates atomically', () async {
    final goal = await goalRepo.create(
      name: 'Build App',
      description: 'Flutter app',
      emoji: '📱',
      colorHex: 0xFF4F46E5,
      targetDate: DateTime.now().add(const Duration(days: 30)),
    );
    final ms = await milestoneRepo.create(
      goalId: goal.id,
      title: 'Milestone 1',
      theme: 'Core',
    );
    final t1 = await taskRepo.create(milestoneId: ms.id, text: 'Task 1');
    final t2 = await taskRepo.create(milestoneId: ms.id, text: 'Task 2');

    expect(t1.dueDate, isNull);
    expect(t2.dueDate, isNull);

    final today = DateTime(2026, 9, 12);
    await taskRepo.setDueDates([t1.id, t2.id], today);

    final updated1 = await taskRepo.getById(t1.id);
    final updated2 = await taskRepo.getById(t2.id);

    expect(updated1?.dueDate, equals(today));
    expect(updated2?.dueDate, equals(today));

    await taskRepo.setDueDate(t1.id, null);
    final reset1 = await taskRepo.getById(t1.id);
    expect(reset1?.dueDate, isNull);
  });

  testWidgets('PickGoalTasksSheet displays available goal tasks and supports selection',
      (tester) async {
    final goal = Goal()
      ..id = 1
      ..uid = 'g1'
      ..name = 'Launch Project'
      ..description = ''
      ..emoji = '🚀'
      ..colorHex = 0xFF5B9CF6
      ..createdAt = DateTime(2026, 1, 1)
      ..targetDate = DateTime(2026, 12, 31)
      ..isArchived = false
      ..sortOrder = 1
      ..priority = 1
      ..updatedAt = DateTime(2026, 1, 1);

    final ms = Milestone()
      ..id = 1
      ..uid = 'm1'
      ..title = 'MVP'
      ..theme = 'Build'
      ..sortOrder = 1
      ..isCollapsed = false
      ..goalUid = 'g1'
      ..updatedAt = DateTime(2026, 1, 1);

    final task1 = Task()
      ..id = 101
      ..uid = 't101'
      ..text = 'Design splash screen'
      ..isCompleted = false
      ..dueDate = null
      ..priority = 1
      ..createdAt = DateTime(2026, 1, 1)
      ..sortOrder = 1
      ..milestoneUid = 'm1'
      ..updatedAt = DateTime(2026, 1, 1);

    final task2 = Task()
      ..id = 102
      ..uid = 't102'
      ..text = 'Implement authentication'
      ..isCompleted = false
      ..dueDate = null
      ..priority = 0
      ..createdAt = DateTime(2026, 1, 1)
      ..sortOrder = 2
      ..milestoneUid = 'm1'
      ..updatedAt = DateTime(2026, 1, 1);

    final contexts = [
      TodayTaskContext(task: task1, goal: goal, milestone: ms),
      TodayTaskContext(task: task2, goal: goal, milestone: ms),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeTaskContextsProvider.overrideWith((ref) async => contexts),
          activeGoalsProvider.overrideWith((ref) => Stream.value([goal])),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: PickGoalTasksSheet(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pick Tasks for Today'), findsOneWidget);
    expect(find.text('Design splash screen'), findsOneWidget);
    expect(find.text('Implement authentication'), findsOneWidget);

    // Tap on task 1 tile to select it
    await tester.tap(find.text('Design splash screen'));
    await tester.pumpAndSettle();

    // Verify selection button label updates
    expect(find.text('Add to Today (1)'), findsOneWidget);
    expect(find.text('1 selected'), findsOneWidget);

    // Tap Select All
    await tester.tap(find.text('Select All'));
    await tester.pumpAndSettle();
    expect(find.text('Add to Today (2)'), findsOneWidget);
    expect(find.text('2 selected'), findsOneWidget);

    // Tap Deselect All
    await tester.tap(find.text('Deselect All'));
    await tester.pumpAndSettle();
    expect(find.text('Select Tasks to Add'), findsOneWidget);
  });

  testWidgets('TodayScreen shows Pick Tasks FAB and handles empty state action',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todayDataProvider.overrideWithValue(
            const AsyncData(
              TodayData(total: 0, overdue: 0, dueToday: 0, dueThisWeek: 0),
            ),
          ),
          todayTasksGroupedProvider.overrideWith(
            (ref) async => const TodayTasksData(
              overdue: [],
              dueToday: [],
              thisWeek: [],
              noDueDate: [],
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const TodayScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('All caught up'), findsOneWidget);
    expect(find.text('+ Pick Tasks from Goals'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('Pick Tasks'), findsOneWidget);
  });
}
