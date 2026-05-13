import 'dart:convert';
import 'dart:io';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../db/isar_service.dart';
import '../models/models.dart';
import 'package:uuid/uuid.dart';

class DataExportService {
  DataExportService._();
  static final instance = DataExportService._();

  /// Export all data to a JSON string and save to the downloads-equivalent folder.
  /// Returns the file path on success.
  Future<String> exportToJson() async {
    final db = IsarService.instance.db;

    final goals = await db.goals.where().build().findAll();
    final milestones = await db.milestones.where().build().findAll();
    final tasks = await db.tasks.where().build().findAll();
    final scheduleItems = await db.scheduleItems.where().build().findAll();

    // Load links
    for (final g in goals) {
      await g.milestones.load();
    }
    for (final ms in milestones) {
      await ms.tasks.load();
      await ms.goal.load();
    }
    for (final t in tasks) {
      await t.milestone.load();
    }

    final data = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'goals': goals
          .map((g) => {
                'uid': g.uid,
                'name': g.name,
                'description': g.description,
                'emoji': g.emoji,
                'colorHex': g.colorHex,
                'createdAt': g.createdAt.toIso8601String(),
                'targetDate': g.targetDate.toIso8601String(),
                'isArchived': g.isArchived,
                'sortOrder': g.sortOrder,
              })
          .toList(),
      'milestones': milestones
          .map((ms) => {
                'uid': ms.uid,
                'goalUid': ms.goal.value?.uid ?? '',
                'title': ms.title,
                'theme': ms.theme,
                'dueDate': ms.dueDate?.toIso8601String(),
                'sortOrder': ms.sortOrder,
                'isCollapsed': ms.isCollapsed,
              })
          .toList(),
      'tasks': tasks
          .map((t) => {
                'uid': t.uid,
                'milestoneUid': t.milestone.value?.uid ?? '',
                'text': t.text,
                'isCompleted': t.isCompleted,
                'dueDate': t.dueDate?.toIso8601String(),
                'priority': t.priority,
                'note': t.note,
                'createdAt': t.createdAt.toIso8601String(),
                'completedAt': t.completedAt?.toIso8601String(),
                'sortOrder': t.sortOrder,
              })
          .toList(),
      'scheduleItems': scheduleItems
          .map((s) => {
                'uid': s.uid,
                'time': s.time,
                'label': s.label,
                'detail': s.detail,
                'goalUid': s.goalUid,
                'weekdays': s.weekdays,
                'isActive': s.isActive,
                'sortOrder': s.sortOrder,
              })
          .toList(),
    };

    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final file = File('${dir.path}/roadmapx_backup_$ts.json');
    await file.writeAsString(jsonEncode(data));
    return file.path;
  }

  /// Import data from a JSON string. Merges by uid (skips existing).
  Future<int> importFromJson(String jsonStr) async {
    final db = IsarService.instance.db;
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;

    int imported = 0;

    await db.writeTxn(() async {
      // Goals
      final existingGoalUids =
          (await db.goals.where().build().findAll()).map((g) => g.uid).toSet();

      final goalsData = (data['goals'] as List<dynamic>? ?? []);
      final newGoals = <Goal>[];
      for (final gd in goalsData) {
        final uid = gd['uid'] as String;
        if (existingGoalUids.contains(uid)) continue;
        final g = Goal()
          ..uid = uid
          ..name = gd['name'] as String
          ..description = gd['description'] as String? ?? ''
          ..emoji = gd['emoji'] as String? ?? '🎯'
          ..colorHex = gd['colorHex'] as int
          ..createdAt = DateTime.parse(gd['createdAt'] as String)
          ..targetDate = DateTime.parse(gd['targetDate'] as String)
          ..isArchived = gd['isArchived'] as bool? ?? false
          ..sortOrder = gd['sortOrder'] as int? ?? 0;
        newGoals.add(g);
        imported++;
      }
      await db.goals.putAll(newGoals);

      // Build uid→id map for goals
      final goalUidToId = {
        for (final g in await db.goals.where().build().findAll()) g.uid: g.id
      };

      // Milestones
      final existingMsUids = (await db.milestones.where().build().findAll())
          .map((m) => m.uid)
          .toSet();

      final msData = (data['milestones'] as List<dynamic>? ?? []);
      for (final md in msData) {
        final uid = md['uid'] as String;
        if (existingMsUids.contains(uid)) continue;
        final goalUid = md['goalUid'] as String? ?? '';
        final goalId = goalUidToId[goalUid];
        if (goalId == null) continue;
        final ms = Milestone()
          ..uid = uid
          ..title = md['title'] as String
          ..theme = md['theme'] as String? ?? ''
          ..dueDate = md['dueDate'] != null
              ? DateTime.parse(md['dueDate'] as String)
              : null
          ..sortOrder = md['sortOrder'] as int? ?? 0
          ..isCollapsed = md['isCollapsed'] as bool? ?? false;
        await db.milestones.put(ms);
        ms.goal.value = await db.goals.get(goalId);
        await ms.goal.save();
        imported++;
      }

      // Build uid→id map for milestones
      final msUidToId = {
        for (final ms in await db.milestones.where().build().findAll())
          ms.uid: ms.id
      };

      // Tasks
      final existingTaskUids =
          (await db.tasks.where().build().findAll()).map((t) => t.uid).toSet();

      final tasksData = (data['tasks'] as List<dynamic>? ?? []);
      for (final td in tasksData) {
        final uid = td['uid'] as String;
        if (existingTaskUids.contains(uid)) continue;
        final msUid = td['milestoneUid'] as String? ?? '';
        final msId = msUidToId[msUid];
        if (msId == null) continue;
        final t = Task()
          ..uid = uid
          ..text = td['text'] as String
          ..isCompleted = td['isCompleted'] as bool? ?? false
          ..dueDate = td['dueDate'] != null
              ? DateTime.parse(td['dueDate'] as String)
              : null
          ..priority = td['priority'] as int? ?? 0
          ..note = td['note'] as String?
          ..createdAt = DateTime.parse(td['createdAt'] as String)
          ..completedAt = td['completedAt'] != null
              ? DateTime.parse(td['completedAt'] as String)
              : null
          ..sortOrder = td['sortOrder'] as int? ?? 0;
        await db.tasks.put(t);
        t.milestone.value = await db.milestones.get(msId);
        await t.milestone.save();
        imported++;
      }

      // Schedule items
      final existingSUids = (await db.scheduleItems.where().build().findAll())
          .map((s) => s.uid)
          .toSet();

      final schedData = (data['scheduleItems'] as List<dynamic>? ?? []);
      final newSched = <ScheduleItem>[];
      for (final sd in schedData) {
        final uid = sd['uid'] as String;
        if (existingSUids.contains(uid)) continue;
        final s = ScheduleItem()
          ..uid = uid
          ..time = sd['time'] as String
          ..label = sd['label'] as String
          ..detail = sd['detail'] as String? ?? ''
          ..goalUid = sd['goalUid'] as String? ?? ''
          ..weekdays = (sd['weekdays'] as List<dynamic>).cast<int>()
          ..isActive = sd['isActive'] as bool? ?? true
          ..sortOrder = sd['sortOrder'] as int? ?? 0;
        newSched.add(s);
        imported++;
      }
      await db.scheduleItems.putAll(newSched);
    });

    return imported;
  }
}
