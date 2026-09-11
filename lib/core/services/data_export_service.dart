import 'dart:convert';

import 'package:isar_community/isar.dart';

import '../db/isar_service.dart';
import '../models/models.dart';

enum ImportMode { merge, replace }

class ImportCounts {
  const ImportCounts({
    this.goals = 0,
    this.milestones = 0,
    this.tasks = 0,
    this.scheduleItems = 0,
    this.habitCheckins = 0,
    this.scheduleCompletions = 0,
    this.appSettings = 0,
    this.preferences = 0,
  });

  final int goals;
  final int milestones;
  final int tasks;
  final int scheduleItems;
  final int habitCheckins;
  final int scheduleCompletions;
  final int appSettings;
  final int preferences;

  int get total =>
      goals +
      milestones +
      tasks +
      scheduleItems +
      habitCheckins +
      scheduleCompletions +
      appSettings;
}

/// Snapshot serialization shared by file backup/restore and by the sync
/// engine's merge step.
///
/// Format history:
///   v2 — no per-row timestamps. Merge could only insert rows it had never
///        seen, so an edit made elsewhere could never arrive.
///   v3 — carries `updatedAt`/`deletedAt` per row, so merge is last-writer-
///        wins and deletes propagate. Day-level history moved out of the
///        preferences blob into real rows.
class DataExportService {
  DataExportService._();
  static final instance = DataExportService._();

  static const int formatVersion = 3;

  /// Preference keys that v2 backups carried but that are now rows. Restoring
  /// them verbatim would leave dead keys behind and lose the history, so
  /// import converts them instead.
  static const _legacyHabitPrefix = 'habit_checks_';
  static const _legacySchedulePrefix = 'schedule_completion_';

  Future<Map<String, dynamic>> exportData({
    required Map<String, dynamic> preferences,
  }) async {
    final db = IsarService.instance.db;

    // Tombstones are included deliberately: a peer restoring this snapshot
    // has to learn about deletes, not just about surviving rows.
    final goals = await db.goals.where().build().findAll();
    final milestones = await db.milestones.where().build().findAll();
    final tasks = await db.tasks.where().build().findAll();
    final scheduleItems = await db.scheduleItems.where().build().findAll();
    final habitCheckins = await db.habitCheckins.where().build().findAll();
    final scheduleCompletions =
        await db.scheduleCompletions.where().build().findAll();
    final appSettings = await db.appSettings.where().build().findAll();

    return {
      'version': formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'preferences': preferences,
      'goals': goals.map(goalToMap).toList(),
      'milestones': milestones.map(milestoneToMap).toList(),
      'tasks': tasks.map(taskToMap).toList(),
      'scheduleItems': scheduleItems.map(scheduleItemToMap).toList(),
      'habitCheckins': habitCheckins.map(habitCheckinToMap).toList(),
      'scheduleCompletions':
          scheduleCompletions.map(scheduleCompletionToMap).toList(),
      'appSettings': appSettings.map(appSettingToMap).toList(),
    };
  }

  // ── Row serialization ─────────────────────────────────────
  // Public because the sync engine sends the same shapes over the wire.

  static Map<String, dynamic> goalToMap(Goal goal) => {
        'uid': goal.uid,
        'name': goal.name,
        'description': goal.description,
        'emoji': goal.emoji,
        'colorHex': goal.colorHex,
        'createdAt': goal.createdAt.toIso8601String(),
        'targetDate': goal.targetDate.toIso8601String(),
        'isArchived': goal.isArchived,
        'sortOrder': goal.sortOrder,
        'priority': goal.priority,
        'updatedAt': goal.updatedAt.toIso8601String(),
        'deletedAt': goal.deletedAt?.toIso8601String(),
      };

  static Map<String, dynamic> milestoneToMap(Milestone milestone) => {
        'uid': milestone.uid,
        'goalUid': milestone.goalUid,
        'title': milestone.title,
        'theme': milestone.theme,
        'dueDate': milestone.dueDate?.toIso8601String(),
        'sortOrder': milestone.sortOrder,
        'isCollapsed': milestone.isCollapsed,
        'updatedAt': milestone.updatedAt.toIso8601String(),
        'deletedAt': milestone.deletedAt?.toIso8601String(),
      };

  static Map<String, dynamic> taskToMap(Task task) => {
        'uid': task.uid,
        'milestoneUid': task.milestoneUid,
        'text': task.text,
        'isCompleted': task.isCompleted,
        'dueDate': task.dueDate?.toIso8601String(),
        'priority': task.priority,
        'note': task.note,
        'createdAt': task.createdAt.toIso8601String(),
        'completedAt': task.completedAt?.toIso8601String(),
        'sortOrder': task.sortOrder,
        'updatedAt': task.updatedAt.toIso8601String(),
        'deletedAt': task.deletedAt?.toIso8601String(),
      };

  static Map<String, dynamic> scheduleItemToMap(ScheduleItem item) => {
        'uid': item.uid,
        'time': item.time,
        'label': item.label,
        'detail': item.detail,
        'goalUid': item.goalUid,
        'weekdays': item.weekdays,
        'isActive': item.isActive,
        'sortOrder': item.sortOrder,
        'updatedAt': item.updatedAt.toIso8601String(),
        'deletedAt': item.deletedAt?.toIso8601String(),
      };

  static Map<String, dynamic> habitCheckinToMap(HabitCheckin row) => {
        'uid': row.uid,
        'dayKey': row.dayKey,
        'checkIndex': row.checkIndex,
        'isChecked': row.isChecked,
        'updatedAt': row.updatedAt.toIso8601String(),
        'deletedAt': row.deletedAt?.toIso8601String(),
      };

  static Map<String, dynamic> scheduleCompletionToMap(ScheduleCompletion row) =>
      {
        'uid': row.uid,
        'dayKey': row.dayKey,
        'scheduleUid': row.scheduleUid,
        'isCompleted': row.isCompleted,
        'updatedAt': row.updatedAt.toIso8601String(),
        'deletedAt': row.deletedAt?.toIso8601String(),
      };

  static Map<String, dynamic> appSettingToMap(AppSetting row) => {
        'uid': row.uid,
        'value': row.value,
        'updatedAt': row.updatedAt.toIso8601String(),
        'deletedAt': row.deletedAt?.toIso8601String(),
      };

  Future<String> exportToJson({
    required Map<String, dynamic> preferences,
  }) async {
    final data = await exportData(preferences: preferences);
    return jsonEncode(data);
  }

  Future<({ImportCounts counts, Map<String, dynamic> preferences})>
      importFromJson(
    String jsonString, {
    ImportMode mode = ImportMode.merge,
  }) async {
    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
    return importFromMap(decoded, mode: mode);
  }

  // ── Merge ─────────────────────────────────────────────────

  static DateTime? _date(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  /// Last-writer-wins.
  ///
  /// A null [incoming] means the row came from a v2 file, which carried no
  /// timestamps. Those can only be inserted when missing, never used to
  /// overwrite — without a timestamp there is no basis for claiming they are
  /// newer, and assuming they are would let an old backup clobber live data.
  ///
  /// Exact ties resolve to the tombstone so that two devices comparing the
  /// same pair of rows always reach the same answer.
  static bool _incomingWins(
    DateTime? incoming,
    DateTime local, {
    required bool incomingIsTombstone,
  }) {
    if (incoming == null) return false;
    if (incoming.isAfter(local)) return true;
    if (incoming.isAtSameMomentAs(local)) return incomingIsTombstone;
    return false;
  }

  Future<({ImportCounts counts, Map<String, dynamic> preferences})>
      importFromMap(
    Map<String, dynamic> data, {
    ImportMode mode = ImportMode.merge,
  }) async {
    final db = IsarService.instance.db;
    final rawPreferences =
        (data['preferences'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};

    List<dynamic> list(String key) =>
        (data[key] as List<dynamic>? ?? const <dynamic>[]);

    final goalsData = list('goals');
    final milestonesData = list('milestones');
    final tasksData = list('tasks');
    final scheduleData = list('scheduleItems');
    final habitData = list('habitCheckins');
    final completionData = list('scheduleCompletions');
    final settingData = list('appSettings');

    // A v2 snapshot keeps day history inside preferences; lift it into rows so
    // restoring an old backup does not silently drop streaks and heatmaps.
    final legacy = _extractLegacyDayHistory(rawPreferences);
    final preferences = legacy.preferences;

    var goalsImported = 0;
    var milestonesImported = 0;
    var tasksImported = 0;
    var scheduleImported = 0;
    var habitImported = 0;
    var completionImported = 0;
    var settingsImported = 0;

    await db.writeTxn(() async {
      if (mode == ImportMode.replace) {
        await db.tasks.clear();
        await db.milestones.clear();
        await db.goals.clear();
        await db.scheduleItems.clear();
        await db.habitCheckins.clear();
        await db.scheduleCompletions.clear();
        await db.appSettings.clear();
      }

      // ── Goals ──
      for (final raw in goalsData) {
        final item = Map<String, dynamic>.from(raw as Map);
        final uid = (item['uid'] as String?) ?? '';
        if (uid.isEmpty) continue;

        final incomingUpdatedAt = _date(item['updatedAt']);
        final deletedAt = _date(item['deletedAt']);
        final createdAt = _date(item['createdAt']) ?? DateTime.now();
        final existing = await db.goals.filter().uidEqualTo(uid).findFirst();

        if (existing != null &&
            !_incomingWins(incomingUpdatedAt, existing.updatedAt,
                incomingIsTombstone: deletedAt != null)) {
          continue;
        }

        final goal = existing ?? (Goal()..uid = uid);
        goal
          ..name = (item['name'] as String?) ?? ''
          ..description = (item['description'] as String?) ?? ''
          ..emoji = (item['emoji'] as String?) ?? '🎯'
          ..colorHex = (item['colorHex'] as int?) ?? 0xFF4F46E5
          ..createdAt = createdAt
          ..targetDate = _date(item['targetDate']) ?? DateTime.now()
          ..isArchived = (item['isArchived'] as bool?) ?? false
          ..sortOrder = (item['sortOrder'] as int?) ?? 0
          // A v2 snapshot predates priorities; default rather than park the
          // goal on Someday, which is what a raw 0 would mean.
          ..priority = GoalPriority.clamp(item['priority'] as int?)
          ..updatedAt = incomingUpdatedAt ?? createdAt
          ..deletedAt = deletedAt;
        await db.goals.put(goal);
        goalsImported++;
      }

      final goalsByUid = {
        for (final goal in await db.goals.where().build().findAll())
          goal.uid: goal,
      };

      // ── Milestones ──
      for (final raw in milestonesData) {
        final item = Map<String, dynamic>.from(raw as Map);
        final uid = (item['uid'] as String?) ?? '';
        if (uid.isEmpty) continue;

        final goalUid = (item['goalUid'] as String?) ?? '';
        final parent = goalsByUid[goalUid];
        if (parent == null) continue;

        final incomingUpdatedAt = _date(item['updatedAt']);
        final deletedAt = _date(item['deletedAt']);
        final existing =
            await db.milestones.filter().uidEqualTo(uid).findFirst();

        if (existing != null &&
            !_incomingWins(incomingUpdatedAt, existing.updatedAt,
                incomingIsTombstone: deletedAt != null)) {
          continue;
        }

        final milestone = existing ?? (Milestone()..uid = uid);
        milestone
          ..title = (item['title'] as String?) ?? ''
          ..theme = (item['theme'] as String?) ?? ''
          ..dueDate = _date(item['dueDate'])
          ..sortOrder = (item['sortOrder'] as int?) ?? 0
          ..isCollapsed = (item['isCollapsed'] as bool?) ?? false
          ..goalUid = goalUid
          ..updatedAt = incomingUpdatedAt ?? DateTime.now()
          ..deletedAt = deletedAt;
        await db.milestones.put(milestone);
        milestone.goal.value = parent;
        await milestone.goal.save();
        milestonesImported++;
      }

      final milestonesByUid = {
        for (final milestone in await db.milestones.where().build().findAll())
          milestone.uid: milestone,
      };

      // ── Tasks ──
      for (final raw in tasksData) {
        final item = Map<String, dynamic>.from(raw as Map);
        final uid = (item['uid'] as String?) ?? '';
        if (uid.isEmpty) continue;

        final milestoneUid = (item['milestoneUid'] as String?) ?? '';
        final parent = milestonesByUid[milestoneUid];
        if (parent == null) continue;

        final incomingUpdatedAt = _date(item['updatedAt']);
        final deletedAt = _date(item['deletedAt']);
        final createdAt = _date(item['createdAt']) ?? DateTime.now();
        final existing = await db.tasks.filter().uidEqualTo(uid).findFirst();

        if (existing != null &&
            !_incomingWins(incomingUpdatedAt, existing.updatedAt,
                incomingIsTombstone: deletedAt != null)) {
          continue;
        }

        final task = existing ?? (Task()..uid = uid);
        task
          ..text = (item['text'] as String?) ?? ''
          ..isCompleted = (item['isCompleted'] as bool?) ?? false
          ..dueDate = _date(item['dueDate'])
          ..priority = (item['priority'] as int?) ?? 0
          ..note = item['note'] as String?
          ..createdAt = createdAt
          ..completedAt = _date(item['completedAt'])
          ..sortOrder = (item['sortOrder'] as int?) ?? 0
          ..milestoneUid = milestoneUid
          ..updatedAt = incomingUpdatedAt ?? createdAt
          ..deletedAt = deletedAt;
        await db.tasks.put(task);
        task.milestone.value = parent;
        await task.milestone.save();
        tasksImported++;
      }

      // ── Schedule items ──
      for (final raw in scheduleData) {
        final item = Map<String, dynamic>.from(raw as Map);
        final uid = (item['uid'] as String?) ?? '';
        if (uid.isEmpty) continue;

        final incomingUpdatedAt = _date(item['updatedAt']);
        final deletedAt = _date(item['deletedAt']);
        final existing =
            await db.scheduleItems.filter().uidEqualTo(uid).findFirst();

        if (existing != null &&
            !_incomingWins(incomingUpdatedAt, existing.updatedAt,
                incomingIsTombstone: deletedAt != null)) {
          continue;
        }

        final scheduleItem = existing ?? (ScheduleItem()..uid = uid);
        scheduleItem
          ..time = (item['time'] as String?) ?? ''
          ..label = (item['label'] as String?) ?? ''
          ..detail = (item['detail'] as String?) ?? ''
          ..goalUid = (item['goalUid'] as String?) ?? ''
          ..weekdays = (item['weekdays'] as List<dynamic>? ?? const <dynamic>[])
              .map((day) => (day as num).toInt())
              .toList()
          ..isActive = (item['isActive'] as bool?) ?? true
          ..sortOrder = (item['sortOrder'] as int?) ?? 0
          ..updatedAt = incomingUpdatedAt ?? DateTime.now()
          ..deletedAt = deletedAt;
        await db.scheduleItems.put(scheduleItem);
        scheduleImported++;
      }

      // ── Habit check-ins (v3 rows, then anything lifted out of a v2 blob) ──
      for (final raw in [...habitData, ...legacy.habitCheckins]) {
        final item = Map<String, dynamic>.from(raw as Map);
        final uid = (item['uid'] as String?) ?? '';
        if (uid.isEmpty) continue;

        final incomingUpdatedAt = _date(item['updatedAt']);
        final deletedAt = _date(item['deletedAt']);
        final existing =
            await db.habitCheckins.filter().uidEqualTo(uid).findFirst();

        if (existing != null &&
            !_incomingWins(incomingUpdatedAt, existing.updatedAt,
                incomingIsTombstone: deletedAt != null)) {
          continue;
        }

        final row = existing ?? (HabitCheckin()..uid = uid);
        row
          ..dayKey = (item['dayKey'] as String?) ?? ''
          ..checkIndex = (item['checkIndex'] as int?) ?? 0
          ..isChecked = (item['isChecked'] as bool?) ?? false
          ..updatedAt = incomingUpdatedAt ?? DateTime.now()
          ..deletedAt = deletedAt;
        await db.habitCheckins.put(row);
        habitImported++;
      }

      // ── Schedule completions ──
      for (final raw in [...completionData, ...legacy.scheduleCompletions]) {
        final item = Map<String, dynamic>.from(raw as Map);
        final uid = (item['uid'] as String?) ?? '';
        if (uid.isEmpty) continue;

        final incomingUpdatedAt = _date(item['updatedAt']);
        final deletedAt = _date(item['deletedAt']);
        final existing =
            await db.scheduleCompletions.filter().uidEqualTo(uid).findFirst();

        if (existing != null &&
            !_incomingWins(incomingUpdatedAt, existing.updatedAt,
                incomingIsTombstone: deletedAt != null)) {
          continue;
        }

        final row = existing ?? (ScheduleCompletion()..uid = uid);
        row
          ..dayKey = (item['dayKey'] as String?) ?? ''
          ..scheduleUid = (item['scheduleUid'] as String?) ?? ''
          ..isCompleted = (item['isCompleted'] as bool?) ?? false
          ..updatedAt = incomingUpdatedAt ?? DateTime.now()
          ..deletedAt = deletedAt;
        await db.scheduleCompletions.put(row);
        completionImported++;
      }

      // ── Synced preferences ──
      for (final raw in settingData) {
        final item = Map<String, dynamic>.from(raw as Map);
        final uid = (item['uid'] as String?) ?? '';
        if (uid.isEmpty) continue;

        final incomingUpdatedAt = _date(item['updatedAt']);
        final deletedAt = _date(item['deletedAt']);
        final existing =
            await db.appSettings.filter().uidEqualTo(uid).findFirst();

        if (existing != null &&
            !_incomingWins(incomingUpdatedAt, existing.updatedAt,
                incomingIsTombstone: deletedAt != null)) {
          continue;
        }

        final row = existing ?? (AppSetting()..uid = uid);
        row
          ..value = (item['value'] as String?) ?? ''
          ..updatedAt = incomingUpdatedAt ?? DateTime.now()
          ..deletedAt = deletedAt;
        await db.appSettings.put(row);
        settingsImported++;
      }
    });

    return (
      counts: ImportCounts(
        goals: goalsImported,
        milestones: milestonesImported,
        tasks: tasksImported,
        scheduleItems: scheduleImported,
        habitCheckins: habitImported,
        scheduleCompletions: completionImported,
        appSettings: settingsImported,
        preferences: preferences.length,
      ),
      preferences: preferences,
    );
  }

  /// Splits a v2 preferences blob into real preferences plus row maps for the
  /// day-keyed history it used to hold.
  ({
    Map<String, dynamic> preferences,
    List<Map<String, dynamic>> habitCheckins,
    List<Map<String, dynamic>> scheduleCompletions,
  }) _extractLegacyDayHistory(Map<String, dynamic> source) {
    final preferences = <String, dynamic>{};
    final habitCheckins = <Map<String, dynamic>>[];
    final scheduleCompletions = <Map<String, dynamic>>[];

    for (final entry in source.entries) {
      final key = entry.key;

      if (key.startsWith(_legacyHabitPrefix)) {
        final dayKey = key.substring(_legacyHabitPrefix.length);
        // Historical days are dated to the day they describe, so a live edit
        // on another device always outranks a restored archive.
        final stamp = DateTime.tryParse(dayKey) ?? DateTime.now();
        for (final tick in _decodeList(entry.value).asMap().entries) {
          if (!_parseBool(tick.value)) continue;
          habitCheckins.add({
            'uid': HabitCheckin.uidFor(dayKey, tick.key),
            'dayKey': dayKey,
            'checkIndex': tick.key,
            'isChecked': true,
            'updatedAt': stamp.toIso8601String(),
          });
        }
        continue;
      }

      if (key.startsWith(_legacySchedulePrefix)) {
        final dayKey = key.substring(_legacySchedulePrefix.length);
        final stamp = DateTime.tryParse(dayKey) ?? DateTime.now();
        for (final value in _decodeList(entry.value)) {
          final scheduleUid = value?.toString() ?? '';
          if (scheduleUid.isEmpty) continue;
          scheduleCompletions.add({
            'uid': ScheduleCompletion.uidFor(dayKey, scheduleUid),
            'dayKey': dayKey,
            'scheduleUid': scheduleUid,
            'isCompleted': true,
            'updatedAt': stamp.toIso8601String(),
          });
        }
        continue;
      }

      preferences[key] = entry.value;
    }

    return (
      preferences: preferences,
      habitCheckins: habitCheckins,
      scheduleCompletions: scheduleCompletions,
    );
  }

  static List<dynamic> _decodeList(dynamic value) {
    if (value is List) return value;
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) return decoded;
      } catch (_) {
        return const <dynamic>[];
      }
    }
    return const <dynamic>[];
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
