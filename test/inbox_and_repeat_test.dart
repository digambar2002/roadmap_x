import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:roadmap_x/core/db/isar_service.dart';
import 'package:roadmap_x/core/models/models.dart';
import 'package:roadmap_x/core/services/data_export_service.dart';
import 'package:roadmap_x/features/goals/data/goal_repository.dart';
import 'package:roadmap_x/features/milestones/data/milestone_repository.dart';
import 'package:roadmap_x/features/tasks/data/task_repository.dart';
import 'package:roadmap_x/features/tasks/domain/repeat_rule.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('repeat rules', () {
    test('next dates, keeping the time of day', () {
      final fri = DateTime(2026, 11, 13, 9, 30);
      expect(RepeatRule.daily.next(fri), DateTime(2026, 11, 14, 9, 30));
      expect(RepeatRule.weekdays.next(fri), DateTime(2026, 11, 16, 9, 30),
          reason: 'skips the weekend');
      expect(RepeatRule.weekly.next(fri), DateTime(2026, 11, 20, 9, 30));
      expect(
          RepeatRule.monthly.next(DateTime(2026, 1, 31)), DateTime(2026, 2, 28),
          reason: 'month-end clamps');
      expect(
          RepeatRule.yearly.next(DateTime(2028, 2, 29)), DateTime(2029, 2, 28));
    });

    test('parsing', () {
      expect(parseRepeatRule('weekly'), RepeatRule.weekly);
      expect(parseRepeatRule(null), isNull);
      expect(parseRepeatRule('nonsense'), isNull);
    });
  });

  group('database', () {
    late Directory dir;
    late Isar isar;

    setUpAll(() async => Isar.initializeIsarCore(download: true));

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dir = await Directory.systemTemp.createTemp('roadmapx_inbox');
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
        name: 'inbox_${dir.path.hashCode}',
      );
      IsarService.instance.overrideForTesting(isar);
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    Future<Milestone> milestone() async {
      final goal = await GoalRepository.instance.create(
        name: 'Ship v1',
        description: '',
        emoji: '🚀',
        colorHex: 0xFF4F46E5,
        targetDate: DateTime(2027, 1, 1),
      );
      return MilestoneRepository.instance
          .create(goalId: goal.id, title: 'Build', theme: '');
    }

    test('a task can be captured without a goal and moved in later', () async {
      final t = await TaskRepository.instance.create(text: 'Call the bank');
      expect(t.milestoneUid, '');
      expect((await TaskRepository.instance.getInbox()).map((t) => t.text),
          ['Call the bank']);
      final contexts = await TaskRepository.instance.getActiveTaskContexts();
      expect(contexts.single.goal, isNull);

      final ms = await milestone();
      await TaskRepository.instance.moveToMilestone(t.id, ms.id);
      expect(await TaskRepository.instance.getInbox(), isEmpty);
      final moved = await TaskRepository.instance.getById(t.id);
      expect(moved!.milestoneUid, ms.uid);
    });

    test('Inbox tasks survive export and import (backup and sync)', () async {
      await TaskRepository.instance.create(text: 'Buy milk', repeat: 'weekly');
      final json = await DataExportService.instance
          .exportToJson(preferences: const <String, dynamic>{});
      await isar.writeTxn(() => isar.tasks.clear());
      await DataExportService.instance.importFromJson(json);
      final tasks = await isar.tasks.where().findAll();
      expect(tasks.single.text, 'Buy milk');
      expect(tasks.single.milestoneUid, '');
      expect(tasks.single.repeat, 'weekly');
    });

    test('completing a repeating task schedules the next one; undo removes it',
        () async {
      final ms = await milestone();
      final t = await TaskRepository.instance.create(
        milestoneId: ms.id,
        text: 'Weekly review',
        dueDate: DateTime(2026, 11, 13),
        repeat: 'weekly',
      );
      await TaskRepository.instance.toggleComplete(t.id, silent: true);
      var open = await isar.tasks
          .filter()
          .deletedAtIsNull()
          .isCompletedEqualTo(false)
          .findAll();
      expect(open.single.dueDate, DateTime(2026, 11, 20));
      expect(open.single.repeat, 'weekly');
      expect(open.single.milestoneUid, ms.uid);

      // Mis-tap: un-complete it. The next occurrence goes away again.
      await TaskRepository.instance.toggleComplete(t.id, silent: true);
      open = await isar.tasks
          .filter()
          .deletedAtIsNull()
          .isCompletedEqualTo(false)
          .findAll();
      expect(open.single.id, t.id, reason: 'no duplicate left behind');

      // Complete again: exactly one next occurrence.
      await TaskRepository.instance.toggleComplete(t.id, silent: true);
      open = await isar.tasks
          .filter()
          .deletedAtIsNull()
          .isCompletedEqualTo(false)
          .findAll();
      expect(open, hasLength(1));
    });
  });
}
