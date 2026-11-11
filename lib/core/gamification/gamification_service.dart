import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/isar_service.dart';
import '../models/models.dart';
import '../services/habit_checkin_service.dart';
import '../services/habit_customization_service.dart';
import '../services/notification_service.dart';
import 'progress_engine.dart';

enum CompanionKind { plant, pet }

/// Everything the Today card and the Me tab show about progress.
class GameSnapshot {
  const GameSnapshot({
    required this.kind,
    required this.name,
    required this.level,
    required this.health,
    required this.today,
    required this.recentDays,
  });

  final CompanionKind kind;
  final String name;
  final LevelInfo level;

  /// Health at the start of today (0–100).
  final int health;

  /// Today so far. Open tasks are added by the provider, which already
  /// watches them.
  final DayActivity today;

  /// The last seven finished days, oldest first, for the care history.
  final List<DayActivity> recentDays;
}

/// Reads history from the database and runs it through the engine.
class GamificationService {
  GamificationService._();
  static final GamificationService instance = GamificationService._();

  static const kindKey = 'companion_kind';
  static const nameKey = 'companion_name';
  static const startedKey = 'companion_started';

  Isar get _db => IsarService.instance.db;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<GameSnapshot> load({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final today = _day(now ?? DateTime.now());

    final kind = prefs.getString(kindKey) == 'pet'
        ? CompanionKind.pet
        : CompanionKind.plant;
    final name = prefs.getString(nameKey) ??
        (kind == CompanionKind.pet ? 'Mochi' : 'Sprout');

    // The companion is born healthy the first time it is shown, so people
    // upgrading are not greeted by a sick plant for weeks they never saw.
    var started = HabitCheckinService.parseDayKey(
      prefs.getString(startedKey) ?? '',
    );
    if (started == null) {
      started = today;
      await prefs.setString(startedKey, HabitCheckinService.dayKeyFor(today));
    }

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

    // ── Health since the companion was born ───────────────
    final finished = <DayActivity>[];
    for (var d = started;
        d.isBefore(today);
        d = DateTime(d.year, d.month, d.day + 1)) {
      finished.add(activityOn(d));
    }
    final recent = <DayActivity>[
      for (var i = 7; i >= 1; i--)
        activityOn(DateTime(today.year, today.month, today.day - i)),
    ];

    return GameSnapshot(
      kind: kind,
      name: name,
      level: levelFor(xp),
      health: computeHealth(finished),
      today: activityOn(today),
      recentDays: recent,
    );
  }

  Future<void> setCompanion({CompanionKind? kind, String? name}) async {
    final prefs = await SharedPreferences.getInstance();
    if (kind != null) {
      await prefs.setString(
          kindKey, kind == CompanionKind.pet ? 'pet' : 'plant');
    }
    if (name != null && name.trim().isNotEmpty) {
      await prefs.setString(nameKey, name.trim());
    }
  }

  static const remindersKey = 'companion_reminders_enabled';

  /// Re-plans the evening nudge for the current state of today.
  Future<void> syncNudge() async {
    final prefs = await SharedPreferences.getInstance();
    final kind = prefs.getString(kindKey) == 'pet'
        ? CompanionKind.pet
        : CompanionKind.plant;
    final name = prefs.getString(nameKey) ??
        (kind == CompanionKind.pet ? 'Mochi' : 'Sprout');
    await NotificationService.instance.scheduleCompanionNudge(
      doneToday: await anythingDoneToday(),
      name: name,
      enabled: prefs.getBool(remindersKey) ?? true,
    );
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
