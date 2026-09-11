import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:roadmap_x/core/db/db_migration.dart';
import 'package:roadmap_x/core/db/isar_service.dart';
import 'package:roadmap_x/core/models/models.dart';

/// The migration runs on every device, including a brand new one that is about
/// to sign in to an existing account. What it seeds there decides whether the
/// user sees their own habits or those plus a set of strangers.
void main() {
  late Directory dir;
  late Isar isar;

  setUpAll(() async => Isar.initializeIsarCore(download: true));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('roadmapx_mig');
    isar = await Isar.open(
      [
        GoalSchema, MilestoneSchema, TaskSchema, ScheduleItemSchema,
        HabitSchema, HabitCheckinSchema, ScheduleCompletionSchema,
        AppSettingSchema,
      ],
      directory: dir.path,
      name: 'mig_${dir.path.hashCode}',
    );
    IsarService.instance.overrideForTesting(isar);
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<List<Habit>> habits() =>
      isar.habits.filter().deletedAtIsNull().sortBySortOrder().build().findAll();

  test('an upgrade keeps the labels the user already had', () async {
    SharedPreferences.setMockInitialValues({
      'non_neg_0_label': 'Swim 1km',
      'non_neg_1_label': 'Write 500 words',
      'non_neg_2_label': 'Read 20 pages',
      'non_neg_3_label': 'Evening review',
      'habit_checks_2026-09-10': '[true, true, false, false]',
    });
    final prefs = await SharedPreferences.getInstance();

    await DbMigration.instance.run(prefs);

    final result = await habits();
    expect(result.map((h) => h.label).toList(),
        ['Swim 1km', 'Write 500 words', 'Read 20 pages', 'Evening review']);

    // The day's ticks must follow the labels across, keyed by habit.
    final ticks = await isar.habitCheckins
        .filter()
        .dayKeyEqualTo('2026-09-10')
        .isCheckedEqualTo(true)
        .findAll();
    expect(ticks.map((t) => t.habitUid).toSet(),
        {result[0].uid, result[1].uid});

    // Dated far back, or the migration itself would break an existing streak.
    expect(result.first.createdAt.year, lessThan(2020));
  });

  test('a fresh install seeds nothing', () async {
    // This is the second-device case: seeding starters here and then syncing
    // the account's real habits would show the user both sets.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await DbMigration.instance.run(prefs);

    expect(await habits(), isEmpty);
  });

  test('the migration is idempotent', () async {
    SharedPreferences.setMockInitialValues({'non_neg_0_label': 'Swim 1km'});
    final prefs = await SharedPreferences.getInstance();

    await DbMigration.instance.run(prefs);
    final first = (await habits()).length;
    await DbMigration.instance.run(prefs);

    expect((await habits()).length, first);
  });

  test('legacy preference keys are cleared so they cannot drift', () async {
    SharedPreferences.setMockInitialValues({'non_neg_0_label': 'Swim 1km'});
    final prefs = await SharedPreferences.getInstance();

    await DbMigration.instance.run(prefs);

    expect(prefs.containsKey('non_neg_0_label'), isFalse);
  });
}
