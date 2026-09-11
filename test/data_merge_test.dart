import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:roadmap_x/core/db/isar_service.dart';
import 'package:roadmap_x/core/models/models.dart';
import 'package:roadmap_x/core/services/data_export_service.dart';
import 'package:roadmap_x/features/goals/data/goal_repository.dart';

/// The merge is what makes multi-device sync possible, and every one of these
/// cases is a way the previous "skip any uid we already have" import silently
/// lost data.
void main() {
  late Directory dir;
  late Isar isar;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('roadmapx_test');
    isar = await Isar.open(
      [
        GoalSchema,
        MilestoneSchema,
        TaskSchema,
        ScheduleItemSchema,
        HabitCheckinSchema,
        ScheduleCompletionSchema,
        AppSettingSchema,
      ],
      directory: dir.path,
      name: 'test_${dir.path.hashCode}',
    );
    IsarService.instance.overrideForTesting(isar);
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Map<String, dynamic> goalPayload({
    required String uid,
    required String name,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) =>
      {
        'uid': uid,
        'name': name,
        'description': '',
        'emoji': '🎯',
        'colorHex': 0xFF4F46E5,
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
        'targetDate': DateTime(2026, 12, 31).toIso8601String(),
        'isArchived': false,
        'sortOrder': 0,
        if (updatedAt != null) 'updatedAt': updatedAt.toIso8601String(),
        if (deletedAt != null) 'deletedAt': deletedAt.toIso8601String(),
      };

  Future<void> merge(Map<String, dynamic> payload) =>
      DataExportService.instance.importFromMap(payload);

  Future<Goal?> goalByUid(String uid) =>
      isar.goals.filter().uidEqualTo(uid).findFirst();

  test('inserts a goal it has never seen', () async {
    await merge({
      'version': 3,
      'goals': [
        goalPayload(uid: 'g1', name: 'Ship v1', updatedAt: DateTime(2026, 3, 1)),
      ],
    });

    expect((await goalByUid('g1'))?.name, 'Ship v1');
  });

  test('a newer remote edit overwrites the local row', () async {
    await merge({
      'version': 3,
      'goals': [
        goalPayload(uid: 'g1', name: 'Old', updatedAt: DateTime(2026, 3, 1)),
      ],
    });
    await merge({
      'version': 3,
      'goals': [
        goalPayload(uid: 'g1', name: 'New', updatedAt: DateTime(2026, 3, 2)),
      ],
    });

    expect((await goalByUid('g1'))?.name, 'New');
  });

  test('an older remote edit is discarded', () async {
    await merge({
      'version': 3,
      'goals': [
        goalPayload(uid: 'g1', name: 'Local', updatedAt: DateTime(2026, 3, 5)),
      ],
    });
    await merge({
      'version': 3,
      'goals': [
        goalPayload(uid: 'g1', name: 'Stale', updatedAt: DateTime(2026, 3, 1)),
      ],
    });

    expect((await goalByUid('g1'))?.name, 'Local');
  });

  test('a tombstone propagates instead of resurrecting the row', () async {
    await merge({
      'version': 3,
      'goals': [
        goalPayload(uid: 'g1', name: 'Doomed', updatedAt: DateTime(2026, 3, 1)),
      ],
    });
    await merge({
      'version': 3,
      'goals': [
        goalPayload(
          uid: 'g1',
          name: 'Doomed',
          updatedAt: DateTime(2026, 3, 2),
          deletedAt: DateTime(2026, 3, 2),
        ),
      ],
    });

    expect((await goalByUid('g1'))?.deletedAt, isNotNull);
  });

  test('a v2 row without timestamps never overwrites live data', () async {
    await merge({
      'version': 3,
      'goals': [
        goalPayload(uid: 'g1', name: 'Live', updatedAt: DateTime(2026, 3, 5)),
      ],
    });
    // No updatedAt at all — exactly what an old backup file carries.
    await merge({
      'version': 2,
      'goals': [goalPayload(uid: 'g1', name: 'Ancient')],
    });

    expect((await goalByUid('g1'))?.name, 'Live');
  });

  test('a v2 row is still inserted when nothing local matches', () async {
    await merge({
      'version': 2,
      'goals': [goalPayload(uid: 'g1', name: 'Restored')],
    });

    expect((await goalByUid('g1'))?.name, 'Restored');
  });

  test('two devices ticking different habit boxes both survive', () async {
    // Device A ticked box 0 this morning.
    await merge({
      'version': 3,
      'habitCheckins': [
        {
          'uid': '2026-09-11#0',
          'dayKey': '2026-09-11',
          'checkIndex': 0,
          'isChecked': true,
          'updatedAt': DateTime(2026, 9, 11, 8).toIso8601String(),
        },
      ],
    });
    // Device B ticked box 2, without ever seeing A's write.
    await merge({
      'version': 3,
      'habitCheckins': [
        {
          'uid': '2026-09-11#2',
          'dayKey': '2026-09-11',
          'checkIndex': 2,
          'isChecked': true,
          'updatedAt': DateTime(2026, 9, 11, 9).toIso8601String(),
        },
      ],
    });

    final ticked = await isar.habitCheckins
        .filter()
        .dayKeyEqualTo('2026-09-11')
        .isCheckedEqualTo(true)
        .findAll();

    expect(ticked.map((row) => row.checkIndex).toSet(), {0, 2});
  });

  test('a v2 preferences blob is lifted into habit rows', () async {
    await merge({
      'version': 2,
      'preferences': {
        'habit_checks_2026-09-10': '[true, true, false, true]',
        'user_name': 'Digambar',
      },
    });

    final ticked = await isar.habitCheckins
        .filter()
        .dayKeyEqualTo('2026-09-10')
        .isCheckedEqualTo(true)
        .findAll();

    expect(ticked.map((row) => row.checkIndex).toSet(), {0, 1, 3});
  });

  test('day history is stripped from the restored preferences map', () async {
    final result = await DataExportService.instance.importFromMap({
      'version': 2,
      'preferences': {
        'habit_checks_2026-09-10': '[true]',
        'schedule_completion_2026-09-10': '["s1"]',
        'user_name': 'Digambar',
      },
    });

    expect(result.preferences.keys, ['user_name']);
  });

  test('children attach to their parent by uid, not by local id', () async {
    await merge({
      'version': 3,
      'goals': [
        goalPayload(uid: 'g1', name: 'Goal', updatedAt: DateTime(2026, 3, 1)),
      ],
      'milestones': [
        {
          'uid': 'm1',
          'goalUid': 'g1',
          'title': 'Phase 1',
          'theme': '',
          'sortOrder': 0,
          'isCollapsed': false,
          'updatedAt': DateTime(2026, 3, 1).toIso8601String(),
        },
      ],
      'tasks': [
        {
          'uid': 't1',
          'milestoneUid': 'm1',
          'text': 'Do the thing',
          'isCompleted': false,
          'priority': 0,
          'createdAt': DateTime(2026, 3, 1).toIso8601String(),
          'sortOrder': 0,
          'updatedAt': DateTime(2026, 3, 1).toIso8601String(),
        },
      ],
    });

    final task = await isar.tasks.filter().uidEqualTo('t1').findFirst();
    await task!.milestone.load();
    final milestone = task.milestone.value!;
    await milestone.goal.load();

    expect(milestone.uid, 'm1');
    expect(milestone.goal.value?.uid, 'g1');
  });

  test('synced settings merge so habit labels match their tick rows', () async {
    await merge({
      'version': 3,
      'appSettings': [
        {
          'uid': 'non_neg_0_label',
          'value': '"Morning workout"',
          'updatedAt': DateTime(2026, 9, 1).toIso8601String(),
        },
      ],
    });
    await merge({
      'version': 3,
      'appSettings': [
        {
          'uid': 'non_neg_0_label',
          'value': '"Swim 1km"',
          'updatedAt': DateTime(2026, 9, 5).toIso8601String(),
        },
      ],
    });

    final row =
        await isar.appSettings.filter().uidEqualTo('non_neg_0_label').findFirst();
    expect(row?.value, '"Swim 1km"');
  });

  test('a delete wins over an edit made at the same instant', () async {
    // Both devices write at the same millisecond; they must still agree on the
    // outcome, or they diverge permanently.
    final instant = DateTime(2026, 3, 1, 12, 0, 0);
    await merge({
      'version': 3,
      'goals': [goalPayload(uid: 'g1', name: 'Edited', updatedAt: instant)],
    });
    await merge({
      'version': 3,
      'goals': [
        goalPayload(
          uid: 'g1',
          name: 'Edited',
          updatedAt: instant,
          deletedAt: instant,
        ),
      ],
    });

    expect((await goalByUid('g1'))?.deletedAt, isNotNull);
  });

  test('a goal without a priority defaults to Active, not Someday', () async {
    // v2 snapshots have no priority field. Falling through to a raw 0 would
    // mean "Someday", quietly removing every restored goal from the dashboard.
    await merge({
      'version': 2,
      'goals': [goalPayload(uid: 'g1', name: 'Restored')],
    });

    expect((await goalByUid('g1'))?.priority, GoalPriority.active);
  });

  test('priority survives a round trip', () async {
    final payload = goalPayload(
      uid: 'g1',
      name: 'Focused',
      updatedAt: DateTime(2026, 3, 1),
    )..['priority'] = GoalPriority.focus;
    await merge({'version': 3, 'goals': [payload]});

    expect((await goalByUid('g1'))?.priority, GoalPriority.focus);
  });

  test('an out-of-range priority is clamped rather than stored', () async {
    final payload = goalPayload(
      uid: 'g1',
      name: 'Odd',
      updatedAt: DateTime(2026, 3, 1),
    )..['priority'] = 99;
    await merge({'version': 3, 'goals': [payload]});

    expect((await goalByUid('g1'))?.priority, GoalPriority.focus);
  });

  test('goals sort Focus first, keeping manual order within a band', () async {
    Goal goal(String uid, int priority, int sortOrder) => Goal()
      ..uid = uid
      ..name = uid
      ..description = ''
      ..emoji = '🎯'
      ..colorHex = 0
      ..createdAt = DateTime(2026, 1, 1)
      ..targetDate = DateTime(2026, 12, 31)
      ..isArchived = false
      ..sortOrder = sortOrder
      ..priority = priority
      ..updatedAt = DateTime(2026, 1, 1);

    final sorted = GoalRepository.sortByPriority([
      goal('active-b', GoalPriority.active, 1),
      goal('someday', GoalPriority.someday, 0),
      goal('focus', GoalPriority.focus, 5),
      goal('active-a', GoalPriority.active, 0),
    ]);

    expect(sorted.map((g) => g.uid).toList(),
        ['focus', 'active-a', 'active-b', 'someday']);
  });
}
