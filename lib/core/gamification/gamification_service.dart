import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/isar_service.dart';
import '../models/models.dart';
import '../services/habit_checkin_service.dart';
import '../services/habit_customization_service.dart';
import '../services/notification_service.dart';
import '../../features/pet/data/pet_repository.dart';
import '../../features/pet/domain/pet_domain.dart';
import 'progress_engine.dart';

/// Everything the Today card and the Me tab show about progress.
class GameSnapshot {
  const GameSnapshot({
    required this.level,
    required this.today,
    required this.recentDays,
  });

  final LevelInfo level;

  /// Today so far. Open tasks are added by the provider, which already
  /// watches them.
  final DayActivity today;

  /// The last seven finished days, oldest first.
  final List<DayActivity> recentDays;
}

/// Reads history from the database and runs it through the engine.
class GamificationService {
  GamificationService._();
  static final GamificationService instance = GamificationService._();

  Isar get _db => IsarService.instance.db;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<GameSnapshot> load({DateTime? now}) async {
    final today = _day(now ?? DateTime.now());

    // ── Load history ────────────────────────────────────────
    final habits = await _db.habits.filter().deletedAtIsNull().findAll();
    final meta = <String, HabitCustomization>{};
    for (final h in habits) {
      try {
        meta[h.uid] = await HabitCustomizationService.instance.get(h.uid);
      } catch (_) {
        meta[h.uid] = const HabitCustomization();
      }
    }
    final habitUids = {for (final h in habits) h.uid};

    final checkins = await _db.habitCheckins
        .filter()
        .deletedAtIsNull()
        .isCheckedEqualTo(true)
        .findAll();
    final checkedByDay = <String, Set<String>>{};
    for (final c in checkins) {
      if (!habitUids.contains(c.habitUid)) continue;
      checkedByDay.putIfAbsent(c.dayKey, () => <String>{}).add(c.habitUid);
    }

    final tasks = await _db.tasks.filter().deletedAtIsNull().findAll();
    final tasksDoneByDay = <String, int>{};
    var tasksDone = 0;
    for (final t in tasks) {
      if (!t.isCompleted) continue;
      tasksDone++;
      final at = t.completedAt;
      if (at == null) continue;
      final key = HabitCheckinService.dayKeyFor(at);
      tasksDoneByDay[key] = (tasksDoneByDay[key] ?? 0) + 1;
    }

    DayActivity activityOn(DateTime day) {
      final key = HabitCheckinService.dayKeyFor(day);
      final due = habits
          .where((h) =>
              !_day(h.createdAt).isAfter(day) &&
              (meta[h.uid] ?? const HabitCustomization())
                  .isScheduledForWeekday(day.weekday))
          .map((h) => h.uid)
          .toSet();
      final checked = checkedByDay[key] ?? const <String>{};
      return DayActivity(
        day: day,
        habitsDue: due.length,
        habitsDone: checked.intersection(due).length,
        tasksDone: tasksDoneByDay[key] ?? 0,
      );
    }

    // ── XP over all history ────────────────────────────────
    final activeDays = <String>{...checkedByDay.keys, ...tasksDoneByDay.keys};
    var perfectDays = 0;
    for (final key in activeDays) {
      final day = HabitCheckinService.parseDayKey(key);
      if (day == null || day.isAfter(today)) continue;
      if (activityOn(_day(day)).isPerfect) perfectDays++;
    }
    final habitTicks =
        checkedByDay.values.fold<int>(0, (sum, set) => sum + set.length);

    // A milestone is done when it has tasks and all are complete; a goal
    // when all of its milestones are.
    final milestones =
        await _db.milestones.filter().deletedAtIsNull().findAll();
    final tasksByMilestone = <String, List<Task>>{};
    for (final t in tasks) {
      tasksByMilestone.putIfAbsent(t.milestoneUid, () => []).add(t);
    }
    final doneMilestones = <String>{};
    final milestonesByGoal = <String, List<Milestone>>{};
    for (final m in milestones) {
      milestonesByGoal.putIfAbsent(m.goalUid, () => []).add(m);
      final ts = tasksByMilestone[m.uid] ?? const <Task>[];
      if (ts.isNotEmpty && ts.every((t) => t.isCompleted)) {
        doneMilestones.add(m.uid);
      }
    }
    final goalsDone = milestonesByGoal.values
        .where((ms) =>
            ms.isNotEmpty && ms.every((m) => doneMilestones.contains(m.uid)))
        .length;

    final xp = computeXp(
      habitTicks: habitTicks,
      tasksDone: tasksDone,
      perfectDays: perfectDays,
      milestonesDone: doneMilestones.length,
      goalsDone: goalsDone,
    );

    final recent = <DayActivity>[
      for (var i = 7; i >= 1; i--)
        activityOn(DateTime(today.year, today.month, today.day - i)),
    ];

    return GameSnapshot(
      level: levelFor(xp),
      today: activityOn(today),
      recentDays: recent,
    );
  }

  static const remindersKey = 'companion_reminders_enabled';

  /// Plans the reminder for when the pet will next run low on something,
  /// moved into waking hours. No pet, no reminder.
  Future<void> syncNudge({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(remindersKey) ?? true;
    final pet = await PetRepository.instance.load();
    if (pet == null || !enabled) {
      await NotificationService.instance.cancelCompanionNudge();
      return;
    }
    final current = now ?? DateTime.now();
    final next = pet.decayed(current).nextLow();
    await NotificationService.instance.scheduleCompanionNudge(
      at: nudgeTime(next.at, current),
      name: pet.name,
      complaint: next.need.complaint,
    );
  }

  /// Keeps reminders between 9:00 and 21:00, and at least a minute out.
  /// A pet that is already low is reminded about at 20:00 (or tomorrow
  /// morning if that has passed).
  static DateTime nudgeTime(DateTime lowAt, DateTime now) {
    var at = lowAt;
    if (!at.isAfter(now)) at = DateTime(now.year, now.month, now.day, 20);
    if (!at.isAfter(now.add(const Duration(minutes: 1)))) {
      at = DateTime(now.year, now.month, now.day + 1, 9);
    }
    if (at.hour < 9) at = DateTime(at.year, at.month, at.day, 9);
    if (at.hour >= 21) at = DateTime(at.year, at.month, at.day + 1, 9);
    return at;
  }

  /// True when anything has been ticked or completed today. Used to decide
  /// whether tonight's companion nudge is still needed.
  Future<bool> anythingDoneToday() async {
    final today = _day(DateTime.now());
    final key = HabitCheckinService.dayKeyFor(today);
    final checkin = await _db.habitCheckins
        .filter()
        .dayKeyEqualTo(key)
        .deletedAtIsNull()
        .isCheckedEqualTo(true)
        .findFirst();
    if (checkin != null) return true;
    final task = await _db.tasks
        .filter()
        .deletedAtIsNull()
        .isCompletedEqualTo(true)
        .completedAtGreaterThan(today, include: true)
        .findFirst();
    return task != null;
  }
}
