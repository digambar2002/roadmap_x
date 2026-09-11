import 'dart:convert';

import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'isar_service.dart';

/// One-time upgrades of existing on-device data to the sync-capable schema.
///
/// Isar backfills newly added fields with type defaults, so rows written by a
/// pre-sync build come back with `updatedAt` at the epoch and empty
/// denormalized foreign keys. Left alone they would either lose every merge
/// (an epoch timestamp always loses last-writer-wins) or fail to re-attach to
/// their parent after a round trip through the server.
class DbMigration {
  DbMigration._();
  static final DbMigration instance = DbMigration._();

  static const _syncSchemaVersionKey = 'db_sync_schema_version';
  static const _currentVersion = 2;

  Isar get _db => IsarService.instance.db;

  /// Safe to call on every launch; it no-ops once the stored version matches.
  Future<void> run(SharedPreferences prefs) async {
    final from = prefs.getInt(_syncSchemaVersionKey) ?? 0;
    if (from >= _currentVersion) return;

    if (from < 1) {
      await _stampSyncMetadata();
      await _backfillParentUids();
      await _migrateHabitChecksFromPrefs(prefs);
      await _migrateScheduleCompletionsFromPrefs(prefs);
    }

    if (from < 2) {
      await _seedGoalPriorities();
    }

    await prefs.setInt(_syncSchemaVersionKey, _currentVersion);
  }

  /// Gives every pre-existing goal the default priority.
  ///
  /// Isar backfills a new non-nullable int with 0, which here means "Someday"
  /// — so without this every goal a user already had would silently disappear
  /// from the dashboard the moment they updated.
  Future<void> _seedGoalPriorities() async {
    final goals = await _db.goals.where().build().findAll();
    if (goals.isEmpty) return;
    for (final goal in goals) {
      goal.priority = GoalPriority.active;
    }
    await _db.writeTxn(() async => _db.goals.putAll(goals));
  }

  /// Anything older than this was never written by a real clock — it is an
  /// Isar default for a field that did not exist when the row was saved.
  static final _epochSentinel = DateTime(2000);

  static bool _isUnstamped(DateTime value) => value.isBefore(_epochSentinel);

  Future<void> _stampSyncMetadata() async {
    await _db.writeTxn(() async {
      final goals = await _db.goals.where().build().findAll();
      final staleGoals = goals.where((g) => _isUnstamped(g.updatedAt)).toList();
      for (final goal in staleGoals) {
        // Existing rows predate sync, so their real modification time is
        // unknown. createdAt is the best lower bound available and keeps a
        // freshly synced peer from overwriting nothing.
        goal.updatedAt = goal.createdAt;
      }
      if (staleGoals.isNotEmpty) await _db.goals.putAll(staleGoals);

      final milestones = await _db.milestones.where().build().findAll();
      final staleMilestones =
          milestones.where((m) => _isUnstamped(m.updatedAt)).toList();
      for (final milestone in staleMilestones) {
        milestone.updatedAt = milestone.dueDate ?? DateTime.now();
      }
      if (staleMilestones.isNotEmpty) {
        await _db.milestones.putAll(staleMilestones);
      }

      final tasks = await _db.tasks.where().build().findAll();
      final staleTasks = tasks.where((t) => _isUnstamped(t.updatedAt)).toList();
      for (final task in staleTasks) {
        task.updatedAt = task.completedAt ?? task.createdAt;
      }
      if (staleTasks.isNotEmpty) await _db.tasks.putAll(staleTasks);

      final items = await _db.scheduleItems.where().build().findAll();
      final staleItems = items.where((i) => _isUnstamped(i.updatedAt)).toList();
      for (final item in staleItems) {
        item.updatedAt = DateTime.now();
      }
      if (staleItems.isNotEmpty) await _db.scheduleItems.putAll(staleItems);
    });
  }

  /// Copies each row's parent uid out of its IsarLink and onto the row, so it
  /// survives serialization to the server and back.
  Future<void> _backfillParentUids() async {
    final milestones = await _db.milestones.where().build().findAll();
    final needGoalUid = <Milestone>[];
    for (final milestone in milestones) {
      if (milestone.goalUid.isNotEmpty) continue;
      await milestone.goal.load();
      final uid = milestone.goal.value?.uid;
      if (uid == null) continue;
      milestone.goalUid = uid;
      needGoalUid.add(milestone);
    }

    final tasks = await _db.tasks.where().build().findAll();
    final needMilestoneUid = <Task>[];
    for (final task in tasks) {
      if (task.milestoneUid.isNotEmpty) continue;
      await task.milestone.load();
      final uid = task.milestone.value?.uid;
      if (uid == null) continue;
      task.milestoneUid = uid;
      needMilestoneUid.add(task);
    }

    if (needGoalUid.isEmpty && needMilestoneUid.isEmpty) return;
    await _db.writeTxn(() async {
      if (needGoalUid.isNotEmpty) await _db.milestones.putAll(needGoalUid);
      if (needMilestoneUid.isNotEmpty) await _db.tasks.putAll(needMilestoneUid);
    });
  }

  /// Moves `habit_checks_<day>` out of SharedPreferences and into per-checkbox
  /// rows. A JSON blob keyed by day can only be merged wholesale, which loses
  /// one device's ticks whenever both devices touch the same day.
  Future<void> _migrateHabitChecksFromPrefs(SharedPreferences prefs) async {
    const prefix = 'habit_checks_';
    final keys = prefs.getKeys().where((k) => k.startsWith(prefix)).toList();
    if (keys.isEmpty) return;

    final rows = <HabitCheckin>[];
    final now = DateTime.now();
    for (final key in keys) {
      final dayKey = key.substring(prefix.length);
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) continue;
      List<dynamic> decoded;
      try {
        decoded = jsonDecode(raw) as List<dynamic>;
      } catch (_) {
        continue;
      }
      for (var i = 0; i < decoded.length; i++) {
        if (!_parseBool(decoded[i])) continue;
        rows.add(
          HabitCheckin()
            ..uid = HabitCheckin.uidFor(dayKey, i)
            ..dayKey = dayKey
            ..checkIndex = i
            ..isChecked = true
            // Past days are historical fact, not a live edit. Dating them to
            // the day they describe keeps a peer's newer edit winning.
            ..updatedAt = DateTime.tryParse(dayKey) ?? now,
        );
      }
    }
    if (rows.isEmpty) return;

    await _db.writeTxn(() async => _db.habitCheckins.putAll(rows));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  /// Same treatment for `schedule_completion_<day>`.
  Future<void> _migrateScheduleCompletionsFromPrefs(
    SharedPreferences prefs,
  ) async {
    const prefix = 'schedule_completion_';
    final keys = prefs.getKeys().where((k) => k.startsWith(prefix)).toList();
    if (keys.isEmpty) return;

    final rows = <ScheduleCompletion>[];
    final now = DateTime.now();
    for (final key in keys) {
      final dayKey = key.substring(prefix.length);
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) continue;
      List<dynamic> decoded;
      try {
        decoded = jsonDecode(raw) as List<dynamic>;
      } catch (_) {
        continue;
      }
      for (final entry in decoded) {
        final scheduleUid = entry?.toString() ?? '';
        if (scheduleUid.isEmpty) continue;
        rows.add(
          ScheduleCompletion()
            ..uid = ScheduleCompletion.uidFor(dayKey, scheduleUid)
            ..dayKey = dayKey
            ..scheduleUid = scheduleUid
            ..isCompleted = true
            ..updatedAt = DateTime.tryParse(dayKey) ?? now,
        );
      }
    }
    if (rows.isEmpty) return;

    await _db.writeTxn(() async => _db.scheduleCompletions.putAll(rows));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  static bool _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is int) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1';
    }
    return false;
  }
}
