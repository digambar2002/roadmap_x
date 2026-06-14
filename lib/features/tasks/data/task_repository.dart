import 'package:isar_community/isar.dart';
import 'package:uuid/uuid.dart';
import '../../../core/db/isar_service.dart';
import '../../../core/models/models.dart';
import '../../../core/services/backup_service.dart';
import '../../../core/models/today_task.dart';

class TaskRepository {
  TaskRepository._();
  static final TaskRepository instance = TaskRepository._();

  Isar get _db => IsarService.instance.db;
  static const _uuid = Uuid();

  // ── Streams ──────────────────────────────────────────────
  Stream<List<Task>> watchForMilestone(int milestoneId) => _db.tasks
      .filter()
      .milestone((q) => q.idEqualTo(milestoneId))
      .sortBySortOrder()
      .build()
      .watch(fireImmediately: true);

  // ── Reads ─────────────────────────────────────────────────
  Future<List<Task>> getForMilestone(int milestoneId) => _db.tasks
      .filter()
      .milestone((q) => q.idEqualTo(milestoneId))
      .sortBySortOrder()
      .build()
      .findAll();

  Future<List<Task>> getAllCompleted() =>
      _db.tasks.filter().isCompletedEqualTo(true).findAll();

  Future<Task?> getById(int id) => _db.tasks.get(id);
  Stream<List<Task>> watchAllTasks() =>
      _db.tasks.where().build().watch(fireImmediately: true);

  Future<List<TodayTaskContext>> getNextTasksForGoal(
    String goalUid, {
    int limit = 3,
  }) async {
    if (goalUid.isEmpty) return [];
    final goal = await _db.goals.filter().uidEqualTo(goalUid).findFirst();
    if (goal == null) return [];

    final tasks = await _db.tasks
        .filter()
        .isCompletedEqualTo(false)
        .sortByPriorityDesc()
        .thenByDueDate()
        .thenBySortOrder()
        .findAll();
    final contexts = await _toContexts(tasks);
    return contexts.where((ctx) => ctx.goal?.id == goal.id).take(limit).toList();
  }

  Future<List<Task>> getAll() => _db.tasks.where().build().findAll();

  Future<List<TodayTaskContext>> getActiveTaskContexts() async {
    final tasks = await _db.tasks
        .filter()
        .isCompletedEqualTo(false)
        .sortByDueDate()
        .thenBySortOrder()
        .findAll();
    return _toContexts(tasks);
  }

  Future<List<TodayTaskContext>> getFocusTasks(int goalId) async {
    final tasks = await _db.tasks
        .filter()
        .isCompletedEqualTo(false)
        .sortByPriorityDesc()
        .thenByDueDate()
        .findAll();
    final contexts = await _toContexts(tasks);
    return contexts.where((ctx) => ctx.goal?.id == goalId).take(5).toList();
  }

  Future<List<TodayTaskContext>> getTodayTasks() async {
    final contexts = await getActiveTaskContexts();
    return contexts
        .where((ctx) => ctx.isDueToday || ctx.isOverdue || ctx.isDueThisWeek)
        .toList();
  }

  // ── Writes ────────────────────────────────────────────────
  Future<Task> create({
    required int milestoneId,
    required String text,
    int priority = 0,
    DateTime? dueDate,
    String? note,
  }) async {
    final ms = await _db.milestones.get(milestoneId);
    if (ms == null) throw Exception('Milestone not found: $milestoneId');

    final task = Task()
      ..uid = _uuid.v4()
      ..text = text
      ..isCompleted = false
      ..dueDate = dueDate
      ..priority = priority
      ..note = note
      ..createdAt = DateTime.now()
      ..completedAt = null
      ..sortOrder = await _nextSortOrder(milestoneId);
    task.milestone.value = ms;

    await _db.writeTxn(() async {
      await _db.tasks.put(task);
      await task.milestone.save();
    });
    await BackupService.instance.scheduleBackup();
    return task;
  }

  Future<void> update(Task task) async {
    await _db.writeTxn(() async {
      await _db.tasks.put(task);
    });
    await BackupService.instance.scheduleBackup();
  }

  Future<void> toggleComplete(int id) async {
    final task = await _db.tasks.get(id);
    if (task == null) return;
    task.isCompleted = !task.isCompleted;
    task.completedAt = task.isCompleted ? DateTime.now() : null;
    await _db.writeTxn(() async => _db.tasks.put(task));
    await BackupService.instance.scheduleBackup();
  }

  Future<void> delete(int id) async {
    await _db.writeTxn(() async => _db.tasks.delete(id));
    await BackupService.instance.scheduleBackup();
  }

  Future<void> reorder(List<Task> tasks) async {
    await _db.writeTxn(() async {
      for (int i = 0; i < tasks.length; i++) {
        tasks[i].sortOrder = i;
      }
      await _db.tasks.putAll(tasks);
    });
    await BackupService.instance.scheduleBackup();
  }

  Future<int> _nextSortOrder(int milestoneId) async {
    final last = await _db.tasks
        .filter()
        .milestone((q) => q.idEqualTo(milestoneId))
        .sortBySortOrderDesc()
        .limit(1)
        .findFirst();
    return (last?.sortOrder ?? -1) + 1;
  }

  Future<List<TodayTaskContext>> _toContexts(List<Task> tasks) async {
    final contexts = <TodayTaskContext>[];
    for (final task in tasks) {
      await task.milestone.load();
      final milestone = task.milestone.value;
      Goal? goal;
      if (milestone != null) {
        await milestone.goal.load();
        goal = milestone.goal.value;
      }
      contexts.add(
        TodayTaskContext(
          task: task,
          goal: goal,
          milestone: milestone,
        ),
      );
    }
    return contexts;
  }
}
