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
    this.preferences = 0,
  });

  final int goals;
  final int milestones;
  final int tasks;
  final int scheduleItems;
  final int preferences;

  int get total => goals + milestones + tasks + scheduleItems;
}

class DataExportService {
  DataExportService._();
  static final instance = DataExportService._();

  Future<Map<String, dynamic>> exportData({
    required Map<String, dynamic> preferences,
  }) async {
    final db = IsarService.instance.db;

    final goals = await db.goals.where().build().findAll();
    final milestones = await db.milestones.where().build().findAll();
    final tasks = await db.tasks.where().build().findAll();
    final scheduleItems = await db.scheduleItems.where().build().findAll();

    for (final goal in goals) {
      await goal.milestones.load();
    }
    for (final milestone in milestones) {
      await milestone.goal.load();
      await milestone.tasks.load();
    }
    for (final task in tasks) {
      await task.milestone.load();
    }

    return {
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'preferences': preferences,
      'goals': goals
          .map(
            (goal) => {
              'uid': goal.uid,
              'name': goal.name,
              'description': goal.description,
              'emoji': goal.emoji,
              'colorHex': goal.colorHex,
              'createdAt': goal.createdAt.toIso8601String(),
              'targetDate': goal.targetDate.toIso8601String(),
              'isArchived': goal.isArchived,
              'sortOrder': goal.sortOrder,
            },
          )
          .toList(),
      'milestones': milestones
          .map(
            (milestone) => {
              'uid': milestone.uid,
              'goalUid': milestone.goal.value?.uid ?? '',
              'title': milestone.title,
              'theme': milestone.theme,
              'dueDate': milestone.dueDate?.toIso8601String(),
              'sortOrder': milestone.sortOrder,
              'isCollapsed': milestone.isCollapsed,
            },
          )
          .toList(),
      'tasks': tasks
          .map(
            (task) => {
              'uid': task.uid,
              'milestoneUid': task.milestone.value?.uid ?? '',
              'text': task.text,
              'isCompleted': task.isCompleted,
              'dueDate': task.dueDate?.toIso8601String(),
              'priority': task.priority,
              'note': task.note,
              'createdAt': task.createdAt.toIso8601String(),
              'completedAt': task.completedAt?.toIso8601String(),
              'sortOrder': task.sortOrder,
            },
          )
          .toList(),
      'scheduleItems': scheduleItems
          .map(
            (item) => {
              'uid': item.uid,
              'time': item.time,
              'label': item.label,
              'detail': item.detail,
              'goalUid': item.goalUid,
              'weekdays': item.weekdays,
              'isActive': item.isActive,
              'sortOrder': item.sortOrder,
            },
          )
          .toList(),
    };
  }

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

  Future<({ImportCounts counts, Map<String, dynamic> preferences})>
      importFromMap(
    Map<String, dynamic> data, {
    ImportMode mode = ImportMode.merge,
  }) async {
    final db = IsarService.instance.db;
    final preferences =
        (data['preferences'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};

    final goalsData = (data['goals'] as List<dynamic>? ?? const <dynamic>[]);
    final milestonesData =
        (data['milestones'] as List<dynamic>? ?? const <dynamic>[]);
    final tasksData = (data['tasks'] as List<dynamic>? ?? const <dynamic>[]);
    final scheduleData =
        (data['scheduleItems'] as List<dynamic>? ?? const <dynamic>[]);

    var goalsImported = 0;
    var milestonesImported = 0;
    var tasksImported = 0;
    var scheduleImported = 0;

    await db.writeTxn(() async {
      if (mode == ImportMode.replace) {
        await db.tasks.clear();
        await db.milestones.clear();
        await db.goals.clear();
        await db.scheduleItems.clear();
      }

      final existingGoalUids = (await db.goals.where().build().findAll())
          .map((goal) => goal.uid)
          .toSet();
      final newGoals = <Goal>[];
      for (final raw in goalsData) {
        final item = Map<String, dynamic>.from(raw as Map);
        final uid = (item['uid'] as String?) ?? '';
        if (uid.isEmpty || existingGoalUids.contains(uid)) continue;

        final goal = Goal()
          ..uid = uid
          ..name = (item['name'] as String?) ?? ''
          ..description = (item['description'] as String?) ?? ''
          ..emoji = (item['emoji'] as String?) ?? '🎯'
          ..colorHex = (item['colorHex'] as int?) ?? 0xFF4F46E5
          ..createdAt =
              DateTime.tryParse((item['createdAt'] as String?) ?? '') ??
                  DateTime.now()
          ..targetDate =
              DateTime.tryParse((item['targetDate'] as String?) ?? '') ??
                  DateTime.now()
          ..isArchived = (item['isArchived'] as bool?) ?? false
          ..sortOrder = (item['sortOrder'] as int?) ?? 0;
        newGoals.add(goal);
      }
      if (newGoals.isNotEmpty) {
        await db.goals.putAll(newGoals);
        goalsImported += newGoals.length;
      }

      final goalUidToId = {
        for (final goal in await db.goals.where().build().findAll())
          goal.uid: goal.id,
      };

      final existingMilestoneUids =
          (await db.milestones.where().build().findAll())
              .map((milestone) => milestone.uid)
              .toSet();
      for (final raw in milestonesData) {
        final item = Map<String, dynamic>.from(raw as Map);
        final uid = (item['uid'] as String?) ?? '';
        if (uid.isEmpty || existingMilestoneUids.contains(uid)) continue;

        final goalUid = (item['goalUid'] as String?) ?? '';
        final goalId = goalUidToId[goalUid];
        if (goalId == null) continue;

        final milestone = Milestone()
          ..uid = uid
          ..title = (item['title'] as String?) ?? ''
          ..theme = (item['theme'] as String?) ?? ''
          ..dueDate = DateTime.tryParse((item['dueDate'] as String?) ?? '')
          ..sortOrder = (item['sortOrder'] as int?) ?? 0
          ..isCollapsed = (item['isCollapsed'] as bool?) ?? false;
        await db.milestones.put(milestone);
        milestone.goal.value = await db.goals.get(goalId);
        await milestone.goal.save();
        milestonesImported++;
      }

      final milestoneUidToId = {
        for (final milestone in await db.milestones.where().build().findAll())
          milestone.uid: milestone.id,
      };

      final existingTaskUids = (await db.tasks.where().build().findAll())
          .map((task) => task.uid)
          .toSet();
      for (final raw in tasksData) {
        final item = Map<String, dynamic>.from(raw as Map);
        final uid = (item['uid'] as String?) ?? '';
        if (uid.isEmpty || existingTaskUids.contains(uid)) continue;

        final milestoneUid = (item['milestoneUid'] as String?) ?? '';
        final milestoneId = milestoneUidToId[milestoneUid];
        if (milestoneId == null) continue;

        final task = Task()
          ..uid = uid
          ..text = (item['text'] as String?) ?? ''
          ..isCompleted = (item['isCompleted'] as bool?) ?? false
          ..dueDate = DateTime.tryParse((item['dueDate'] as String?) ?? '')
          ..priority = (item['priority'] as int?) ?? 0
          ..note = item['note'] as String?
          ..createdAt =
              DateTime.tryParse((item['createdAt'] as String?) ?? '') ??
                  DateTime.now()
          ..completedAt =
              DateTime.tryParse((item['completedAt'] as String?) ?? '')
          ..sortOrder = (item['sortOrder'] as int?) ?? 0;
        await db.tasks.put(task);
        task.milestone.value = await db.milestones.get(milestoneId);
        await task.milestone.save();
        tasksImported++;
      }

      final existingScheduleUids =
          (await db.scheduleItems.where().build().findAll())
              .map((item) => item.uid)
              .toSet();
      final newScheduleItems = <ScheduleItem>[];
      for (final raw in scheduleData) {
        final item = Map<String, dynamic>.from(raw as Map);
        final uid = (item['uid'] as String?) ?? '';
        if (uid.isEmpty || existingScheduleUids.contains(uid)) continue;

        final scheduleItem = ScheduleItem()
          ..uid = uid
          ..time = (item['time'] as String?) ?? ''
          ..label = (item['label'] as String?) ?? ''
          ..detail = (item['detail'] as String?) ?? ''
          ..goalUid = (item['goalUid'] as String?) ?? ''
          ..weekdays = (item['weekdays'] as List<dynamic>? ?? const <dynamic>[])
              .map((day) => day as int)
              .toList()
          ..isActive = (item['isActive'] as bool?) ?? true
          ..sortOrder = (item['sortOrder'] as int?) ?? 0;
        newScheduleItems.add(scheduleItem);
      }
      if (newScheduleItems.isNotEmpty) {
        await db.scheduleItems.putAll(newScheduleItems);
        scheduleImported += newScheduleItems.length;
      }
    });

    return (
      counts: ImportCounts(
        goals: goalsImported,
        milestones: milestonesImported,
        tasks: tasksImported,
        scheduleItems: scheduleImported,
        preferences: preferences.length,
      ),
      preferences: preferences,
    );
  }
}
