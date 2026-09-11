import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:roadmap_x/core/db/isar_service.dart';
import 'package:roadmap_x/core/models/models.dart';
import 'package:roadmap_x/core/services/habit_checkin_service.dart';
import 'package:roadmap_x/features/habits/data/habit_repository.dart';

/// Habits are user-defined now, so the streak rules have to cope with the set
/// changing over time.
void main() {
  late Directory dir;
  late Isar isar;

  setUpAll(() async => Isar.initializeIsarCore(download: true));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('roadmapx_habits');
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
      name: 'habits_${dir.path.hashCode}',
    );
    IsarService.instance.overrideForTesting(isar);
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  final service = HabitCheckinService.instance;
  final repo = HabitRepository.instance;

  Future<Habit> addHabit(String label, {DateTime? createdAt}) async {
    final habit = await repo.create(label: label, iconKey: 'run');
    if (createdAt != null) {
      habit.createdAt = createdAt;
      await repo.update(habit);
    }
    return habit;
  }

  test('a day counts only when every habit is ticked', () async {
    final a = await addHabit('Run', createdAt: DateTime(2020));
    final b = await addHabit('Read', createdAt: DateTime(2020));
    final today = DateTime.now();

    await service.setChecked(today, a.uid, true);
    expect(await service.isDayComplete(today), isFalse);

    await service.setChecked(today, b.uid, true);
    expect(await service.isDayComplete(today), isTrue);
  });

  test('unticking a habit reopens the day', () async {
    final a = await addHabit('Run', createdAt: DateTime(2020));
    final today = DateTime.now();

    await service.setChecked(today, a.uid, true);
    expect(await service.isDayComplete(today), isTrue);

    await service.setChecked(today, a.uid, false);
    expect(await service.isDayComplete(today), isFalse);
  });

  test('adding a habit today does not break yesterday', () async {
    // The whole reason Habit carries createdAt: without it, adding a habit
    // would mark every past day incomplete and wipe out an existing streak.
    final old = await addHabit('Run', createdAt: DateTime(2020));
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1);

    await service.setChecked(yesterday, old.uid, true);
    expect(await service.isDayComplete(yesterday), isTrue);

    await addHabit('Brand new habit'); // created today
    expect(await service.isDayComplete(yesterday), isTrue,
        reason: 'a habit that did not exist yesterday is not expected then');
  });

  test('streak survives an incomplete today', () async {
    final habit = await addHabit('Run', createdAt: DateTime(2020));
    final now = DateTime.now();
    for (var i = 1; i <= 3; i++) {
      await service.setChecked(
        DateTime(now.year, now.month, now.day - i),
        habit.uid,
        true,
      );
    }

    // Today is not done yet, but the day is not over either.
    expect(await service.getCurrentStreak(), 3);
  });

  test('no habits means no streak', () async {
    expect(await service.getCurrentStreak(), 0);
    expect(await service.isDayComplete(DateTime.now()), isFalse);
  });

  test('removing a habit keeps its past check-ins', () async {
    final habit = await addHabit('Run', createdAt: DateTime(2020));
    final now = DateTime.now();
    await service.setChecked(now, habit.uid, true);

    await repo.delete(habit.id);

    expect(await repo.count(), 0);
    final rows = await isar.habitCheckins
        .filter()
        .habitUidEqualTo(habit.uid)
        .findAll();
    expect(rows, isNotEmpty, reason: 'history is a record, not a live link');
  });

  test('a deleted habit stops blocking day completion', () async {
    final keep = await addHabit('Run', createdAt: DateTime(2020));
    final drop = await addHabit('Read', createdAt: DateTime(2020));
    final today = DateTime.now();

    await service.setChecked(today, keep.uid, true);
    expect(await service.isDayComplete(today), isFalse);

    await repo.delete(drop.id);
    expect(await service.isDayComplete(today), isTrue);
  });

  test('reorder renumbers without touching identity', () async {
    final a = await addHabit('A');
    final b = await addHabit('B');
    await repo.reorder([b, a]);

    final ordered = await repo.getAll();
    expect(ordered.map((h) => h.uid).toList(), [b.uid, a.uid]);
  });
}
