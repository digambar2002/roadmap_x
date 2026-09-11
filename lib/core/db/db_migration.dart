import 'dart:convert';

import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../../features/habits/data/habit_repository.dart';
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
  static const _currentVersion = 3;

  Isar get _db => IsarService.instance.db;

  /// Safe to call on every launch; it no-ops once the stored version matches.
  Future<void> run(SharedPreferences prefs) async {
    final from = prefs.getInt(_syncSchemaVersionKey) ?? 0;
    if (from >= _currentVersion) return;

    if (from < 1) {
      await _stampSyncMetadata();
      await _backfillParentUids();
      await _migrateScheduleCompletionsFromPrefs(prefs);
    }

    if (from < 2) {
      await _seedGoalPriorities();
    }

    if (from < 3) {
      await _seedHabits(prefs);
      await _rekeyHabitCheckinsByHabitUid();
      await _migrateHabitChecksFromPrefs(prefs);
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

  /// Carries the four fixed slots that used to live in SharedPreferences over
  /// into [Habit] rows.
  ///
  /// Only for an *upgrade*. A brand new install seeds nothing, because it may
  /// be a second device about to sign in: seeding starters there and then
  /// pulling the account's real habits would leave the user looking at both
  /// sets. With no legacy keys there is nothing to preserve anyway, and the
  /// dashboard already prompts an empty list.
  Future<void> _seedHabits(SharedPreferences prefs) async {
    final existing = await _db.habits.filter().deletedAtIsNull().count();
    if (existing > 0) return;

    const legacyKeys = [
      'non_neg_0_label',
      'non_neg_1_label',
      'non_neg_2_label',
      'non_neg_3_label',
    ];

    final isUpgrade = legacyKeys.any(prefs.containsKey);
    if (!isUpgrade) return;

    const uuid = Uuid();
    final rows = <Habit>[];
    for (var i = 0; i < HabitRepository.starterHabits.length; i++) {
      final starter = HabitRepository.starterHabits[i];
      final saved = prefs.getString(legacyKeys[i])?.trim();
      rows.add(
        Habit()
          ..uid = uuid.v4()
          ..label = (saved == null || saved.isEmpty) ? starter.label : saved
          ..iconKey = starter.iconKey
          ..sortOrder = i
          // Dated far back deliberately: these habits applied to every day
          // already on record, so an existing streak must survive the move.
          ..createdAt = DateTime(2000)
          ..updatedAt = DateTime.now(),
      );
    }

    await _db.writeTxn(() async => _db.habits.putAll(rows));

    // They are rows now; leaving them in SharedPreferences would mean two
    // sources of truth that drift apart.
    for (final key in legacyKeys) {
      await prefs.remove(key);
    }
    await _db.writeTxn(() async {
      final stale = await _db.appSettings
          .filter()
          .anyOf(legacyKeys, (q, key) => q.uidEqualTo(key))
          .findAll();
      if (stale.isEmpty) return;
      final now = DateTime.now();
      for (final row in stale) {
        row
          ..deletedAt = now
          ..updatedAt = now;
      }
      await _db.appSettings.putAll(stale);
    });
  }

  /// Converts check-ins keyed by slot position to ones keyed by habit uid.
  ///
  /// Earlier builds stored `"2026-09-11#2"`. The index is only recoverable
  /// from the uid, because the `checkIndex` column no longer exists on the
  /// model — Isar drops a field it cannot see.
  Future<void> _rekeyHabitCheckinsByHabitUid() async {
    final habits = await _db.habits
        .filter()
        .deletedAtIsNull()
        .sortBySortOrder()
        .build()
        .findAll();
    if (habits.isEmpty) return;

    final rows = await _db.habitCheckins.where().build().findAll();
    final converted = <HabitCheckin>[];
    final discarded = <int>[];

    for (final row in rows) {
      if (row.habitUid.isNotEmpty) continue;
      final hash = row.uid.lastIndexOf('#');
      if (hash < 0) continue;
      final index = int.tryParse(row.uid.substring(hash + 1));
      if (index == null || index < 0 || index >= habits.length) {
        // A slot with no habit behind it any more: nothing to attribute the
        // tick to, so drop it rather than invent an owner.
        discarded.add(row.id);
        continue;
      }
      final habitUid = habits[index].uid;
      final dayKey = row.uid.substring(0, hash);
      converted.add(
        HabitCheckin()
          ..uid = HabitCheckin.uidFor(dayKey, habitUid)
          ..dayKey = dayKey
          ..habitUid = habitUid
          ..isChecked = row.isChecked
          ..updatedAt = row.updatedAt
          ..deletedAt = row.deletedAt,
      );
      discarded.add(row.id);
    }

    if (converted.isEmpty && discarded.isEmpty) return;
    await _db.writeTxn(() async {
      await _db.habitCheckins.deleteAll(discarded);
      await _db.habitCheckins.putAll(converted);
    });
  }

  /// Moves `habit_checks_<day>` out of SharedPreferences and into per-habit
  /// rows. A JSON blob keyed by day can only be merged wholesale, which loses
  /// one device's ticks whenever both devices touch the same day.
  Future<void> _migrateHabitChecksFromPrefs(SharedPreferences prefs) async {
    const prefix = 'habit_checks_';
    final keys = prefs.getKeys().where((k) => k.startsWith(prefix)).toList();
    if (keys.isEmpty) return;

    final habits = await _db.habits
        .filter()
        .deletedAtIsNull()
        .sortBySortOrder()
        .build()
        .findAll();

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
      for (var i = 0; i < decoded.length && i < habits.length; i++) {
        if (!_parseBool(decoded[i])) continue;
        rows.add(
          HabitCheckin()
            ..uid = HabitCheckin.uidFor(dayKey, habits[i].uid)
            ..dayKey = dayKey
            ..habitUid = habits[i].uid
            ..isChecked = true
            // Past days are historical fact, not a live edit. Dating them to
            // the day they describe keeps a peer's newer edit winning.
            ..updatedAt = DateTime.tryParse(dayKey) ?? now,
        );
      }
    }

    if (rows.isNotEmpty) {
      await _db.writeTxn(() async => _db.habitCheckins.putAll(rows));
    }
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
