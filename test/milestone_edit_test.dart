import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:roadmap_x/core/db/isar_service.dart';
import 'package:roadmap_x/core/models/models.dart';
import 'package:roadmap_x/features/goals/data/goal_repository.dart';
import 'package:roadmap_x/features/goals/presentation/widgets/create_edit_milestone_sheet.dart';
import 'package:roadmap_x/features/milestones/data/milestone_repository.dart';

/// Milestones are editable: the sheet opens pre-filled and saving writes the
/// new title and theme to the existing row instead of creating another.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Isar isar;

  setUpAll(() async => Isar.initializeIsarCore(download: true));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('roadmapx_ms');
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
      name: 'ms_${dir.path.hashCode}',
    );
    IsarService.instance.overrideForTesting(isar);
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  testWidgets('edits an existing milestone in place', (tester) async {
    late Milestone ms;
    late int goalId;
    await tester.runAsync(() async {
      final goal = await GoalRepository.instance.create(
        name: 'Ship v1',
        description: '',
        emoji: '🚀',
        colorHex: 0xFF4F46E5,
        targetDate: DateTime(2027, 1, 1),
      );
      goalId = goal.id;
      ms = await MilestoneRepository.instance.create(
        goalId: goal.id,
        title: 'Old title',
        theme: 'Old theme',
      );
    });

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        // Plain theme: the app theme fetches Google Fonts over the network,
        // which real-async test time would actually attempt.
        theme: ThemeData.dark(),
        home: Scaffold(
          body: CreateEditMilestoneSheet(goalId: goalId, milestone: ms),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Edit Milestone'), findsOneWidget);
    expect(find.text('Old title'), findsOneWidget, reason: 'pre-filled');

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Old title'), 'New title');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Old theme'), 'New theme');
    await tester.runAsync(() async {
      await tester.tap(find.text('Save Changes'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    late List<Milestone> all;
    await tester.runAsync(() async {
      all = await isar.milestones.filter().deletedAtIsNull().findAll();
    });
    expect(all, hasLength(1), reason: 'edited in place, not duplicated');
    expect(all.single.title, 'New title');
    expect(all.single.theme, 'New theme');
  });
}
