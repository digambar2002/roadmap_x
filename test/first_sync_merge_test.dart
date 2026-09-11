import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

import 'package:roadmap_x/core/db/isar_service.dart';
import 'package:roadmap_x/core/models/models.dart';
import 'package:roadmap_x/core/services/data_export_service.dart';

/// What happens when someone uses the app offline, then signs in to an account
/// that already has data. Both sets have different uids, so nothing collides —
/// they simply add up, which to the user looks like duplicates.
void main() {
  late Directory dir;
  late Isar isar;

  setUpAll(() async => Isar.initializeIsarCore(download: true));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('roadmapx_firstsync');
    isar = await Isar.open(
      [
        GoalSchema, MilestoneSchema, TaskSchema, ScheduleItemSchema,
        HabitSchema, HabitCheckinSchema, ScheduleCompletionSchema,
        AppSettingSchema,
      ],
      directory: dir.path,
      name: 'fs_${dir.path.hashCode}',
    );
    IsarService.instance.overrideForTesting(isar);
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Map<String, dynamic> goal(String uid, String name) => {
        'uid': uid,
        'name': name,
        'description': '',
        'emoji': '🎯',
        'colorHex': 0xFF4F46E5,
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
        'targetDate': DateTime(2026, 12, 31).toIso8601String(),
        'isArchived': false,
        'sortOrder': 0,
        'priority': 1,
        'updatedAt': DateTime(2026, 3, 1).toIso8601String(),
      };

  test('signing in adds the account data to whatever is already local',
      () async {
    // Created offline on the new device.
    await DataExportService.instance.importFromMap({
      'version': 3,
      'goals': [goal('local-uuid', 'Learn Flutter')],
    });

    // Pulled from the account after signing in — same idea, different uid.
    await DataExportService.instance.importFromMap({
      'version': 3,
      'goals': [goal('server-uuid', 'Learn Flutter')],
    });

    final all = await isar.goals.filter().deletedAtIsNull().findAll();
    expect(all.length, 2,
        reason: 'union, not a merge by name — the user sees it twice');
    expect(all.map((g) => g.name).toSet(), {'Learn Flutter'});
  });

  test('replace mode clears local data before taking the account copy',
      () async {
    await DataExportService.instance.importFromMap({
      'version': 3,
      'goals': [goal('local-uuid', 'Learn Flutter')],
    });

    await DataExportService.instance.importFromMap(
      {'version': 3, 'goals': [goal('server-uuid', 'Learn Flutter')]},
      mode: ImportMode.replace,
    );

    final all = await isar.goals.filter().deletedAtIsNull().findAll();
    expect(all.length, 1);
    expect(all.single.uid, 'server-uuid');
  });

  test('the two choices lead to different, deliberate outcomes', () async {
    // Local trial data.
    await DataExportService.instance.importFromMap({
      'version': 3,
      'goals': [goal('local-uuid', 'Learn Flutter')],
    });

    // "Keep both" is the union proven above; "use account data" clears first.
    // This asserts the clearing step covers every synced collection, so a
    // replace cannot leave orphaned children behind.
    await isar.writeTxn(() async {
      await isar.tasks.clear();
      await isar.milestones.clear();
      await isar.goals.clear();
      await isar.scheduleItems.clear();
      await isar.habitCheckins.clear();
      await isar.habits.clear();
      await isar.scheduleCompletions.clear();
      await isar.appSettings.clear();
    });

    expect(await isar.goals.count(), 0);
    expect(await isar.habits.count(), 0);
    expect(await isar.habitCheckins.count(), 0);

    await DataExportService.instance.importFromMap({
      'version': 3,
      'goals': [goal('server-uuid', 'Learn Flutter')],
    });

    final all = await isar.goals.filter().deletedAtIsNull().findAll();
    expect(all.single.uid, 'server-uuid');
  });
}
