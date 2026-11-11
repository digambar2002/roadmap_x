import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:roadmap_x/core/db/isar_service.dart';
import 'package:roadmap_x/core/models/models.dart';
import 'package:roadmap_x/features/ai_goal/data/goal_plan_saver.dart';
import 'package:roadmap_x/features/ai_goal/data/plan_text_parser.dart';
import 'package:roadmap_x/features/ai_goal/presentation/paste_plan_sheet.dart';

const plan = '''
🏃 Run a 10k
Week 1: Base
- Run 3 times
- Stretch daily
Week 2: Build
- Long run on Sunday !
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('paste, preview, rename', (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: PastePlanSheet())),
    ));

    // Nothing typed yet.
    await tester.tap(find.text('Preview'));
    await tester.pump();
    expect(
        find.textContaining('Paste or type your plan first'), findsOneWidget);

    await tester.enterText(find.byType(TextField), plan);
    await tester.tap(find.text('Preview'));
    await tester.pump();

    expect(find.text('Review your goal'), findsOneWidget);
    expect(find.text('2 milestones · 3 tasks'), findsOneWidget);
    expect(find.textContaining('Week 1', findRichText: true), findsOneWidget);
    expect(find.text('Long run on Sunday'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Run a 10k'), findsOneWidget);

    await tester.tap(find.text('Edit text'));
    await tester.pump();
    expect(find.text('Create from text'), findsOneWidget);
  });

  testWidgets('text with no tasks explains what to do', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: PastePlanSheet())),
    ));
    await tester.enterText(find.byType(TextField), 'Just a title');
    await tester.tap(find.text('Preview'));
    await tester.pump();
    expect(find.textContaining('No tasks found'), findsOneWidget);
  });

  group('saving', () {
    late Directory dir;
    late Isar isar;

    setUpAll(() async => Isar.initializeIsarCore(download: true));

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dir = await Directory.systemTemp.createTemp('roadmapx_paste');
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
        name: 'paste_${dir.path.hashCode}',
      );
      IsarService.instance.overrideForTesting(isar);
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('creates the goal, its milestones and tasks in order', () async {
      final id =
          await saveGoalPlan(PlanTextParser.parse(plan), goalName: 'My 10k');
      final goal = await isar.goals.get(id);
      expect(goal!.name, 'My 10k');
      expect(goal.emoji, '🏃');
      final ms = await isar.milestones
          .filter()
          .goalUidEqualTo(goal.uid)
          .sortBySortOrder()
          .findAll();
      expect(ms.map((m) => m.title), ['Week 1', 'Week 2']);
      final tasks = await isar.tasks.where().findAll();
      expect(tasks, hasLength(3));
      expect(
          tasks.firstWhere((t) => t.text == 'Long run on Sunday').priority, 1);
    });
  });
}
