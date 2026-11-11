import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:roadmap_x/core/db/isar_service.dart';
import 'package:roadmap_x/core/gamification/gamification_service.dart';
import 'package:roadmap_x/core/gamification/progress_engine.dart';
import 'package:roadmap_x/core/models/models.dart';
import 'package:roadmap_x/core/services/habit_checkin_service.dart';

/// XP and health come from real history: check-ins and completed tasks.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Isar isar;

  setUpAll(() async => Isar.initializeIsarCore(download: true));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('roadmapx_game');
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
      name: 'game_${dir.path.hashCode}',
    );
    IsarService.instance.overrideForTesting(isar);
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  final today = DateTime(2026, 11, 11);
  DateTime ago(int n) => DateTime(today.year, today.month, today.day - n);

  Future<void> seed() async {
    final habit = Habit()
      ..uid = 'h1'
      ..label = 'Read'
      ..iconKey = 'read'
      ..sortOrder = 0
      ..createdAt = ago(10)
      ..updatedAt = ago(10);
    HabitCheckin tick(DateTime d) => HabitCheckin()
      ..uid = HabitCheckin.uidFor(HabitCheckinService.dayKeyFor(d), 'h1')
      ..dayKey = HabitCheckinService.dayKeyFor(d)
      ..habitUid = 'h1'
      ..isChecked = true
      ..updatedAt = d;
    final task = Task()
      ..uid = 't1'
      ..text = 'Ship'
      ..isCompleted = true
      ..completedAt = ago(1).add(const Duration(hours: 9))
      ..priority = 0
      ..note = null
      ..dueDate = null
      ..sortOrder = 0
      ..milestoneUid = 'm1'
      ..createdAt = ago(5)
      ..updatedAt = ago(1);
    final ms = Milestone()
      ..uid = 'm1'
      ..title = 'v1'
      ..theme = ''
      ..dueDate = null
      ..sortOrder = 0
      ..isCollapsed = false
      ..goalUid = 'g1'
      ..updatedAt = ago(5);
    await isar.writeTxn(() async {
      await isar.habits.put(habit);
      // Ticked 3 and 1 days ago; nothing 2 days ago.
      await isar.habitCheckins.putAll([tick(ago(3)), tick(ago(1))]);
      await isar.tasks.put(task);
      await isar.milestones.put(ms);
    });
  }

  test('XP counts habits, tasks, perfect days and finished milestones',
      () async {
    await seed();
    final snap = await GamificationService.instance.load(now: today);
    // 2 ticks, 1 task, 2 perfect days, 1 milestone done, 1 goal done
    // (its only milestone is complete).
    expect(
      snap.level.xp,
      2 * XpRules.habit +
          1 * XpRules.task +
          2 * XpRules.perfectDay +
          XpRules.milestone +
          XpRules.goal,
    );
  });


  test('today and the last seven days are reported', () async {
    await seed();
    final snap = await GamificationService.instance.load(now: today);
    expect(snap.today.anyDone, isFalse);
    expect(snap.recentDays, hasLength(7));
    expect(snap.recentDays.last.isPerfect, isTrue, reason: 'yesterday');
  });

  group('reminder timing', () {
    final now = DateTime(2026, 11, 11, 10, 0);
    test('fires when the need runs low, during the day', () {
      final at = GamificationService.nudgeTime(DateTime(2026, 11, 11, 15), now);
      expect(at, DateTime(2026, 11, 11, 15));
    });
    test('night-time lows move to 9 am', () {
      expect(GamificationService.nudgeTime(DateTime(2026, 11, 11, 23), now),
          DateTime(2026, 11, 12, 9));
      expect(GamificationService.nudgeTime(DateTime(2026, 11, 12, 4), now),
          DateTime(2026, 11, 12, 9));
    });
    test('already low: tonight at 8, or tomorrow morning if past', () {
      expect(GamificationService.nudgeTime(now, now), DateTime(2026, 11, 11, 20));
      final late = DateTime(2026, 11, 11, 22);
      expect(GamificationService.nudgeTime(late, late), DateTime(2026, 11, 12, 9));
    });
  });
}
