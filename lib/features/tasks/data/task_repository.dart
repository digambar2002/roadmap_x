import 'package:isar_community/isar.dart';
import 'package:uuid/uuid.dart';
import '../../../core/db/isar_service.dart';
import '../../../core/models/models.dart';
import '../../../core/services/local_changes.dart';
import '../../../core/models/today_task.dart';

class TaskRepository {
  TaskRepository._();
  static final TaskRepository instance = TaskRepository._();

  Isar get _db => IsarService.instance.db;
  static const _uuid = Uuid();

  // ── Streams ──────────────────────────────────────────────
  Stream<List<Task>> watchForMilestone(int milestoneId) => _db.tasks
      .filter()
      .deletedAtIsNull()
      .milestone((q) => q.idEqualTo(milestoneId))
      .sortBySortOrder()
      .build()
      .watch(fireImmediately: true);

  // ── Reads ─────────────────────────────────────────────────
  Future<List<Task>> getForMilestone(int milestoneId) => _db.tasks
      .filter()
      .deletedAtIsNull()
      .milestone((q) => q.idEqualTo(milestoneId))
      .sortBySortOrder()
      .build()
      .findAll();

  Future<List<Task>> getAllCompleted() =>
      _db.tasks.filter().deletedAtIsNull().isCompletedEqualTo(true).findAll();

  Future<Task?> getById(int id) async {
    final task = await _db.tasks.get(id);
    return task?.deletedAt == null ? task : null;
  }

  Stream<List<Task>> watchAllTasks() =>
      _db.tasks.filter().deletedAtIsNull().build().watch(fireImmediately: true);

  /// Fires whenever any task changes; used to invalidate derived providers.
  Stream<void> watchTaskActivity() =>
      _db.tasks.watchLazy(fireImmediately: true);

  /// Fires whenever any goal changes (e.g. archived), which affects which
  /// task contexts are visible.
  Stream<void> watchGoalActivity() =>
      _db.goals.watchLazy(fireImmediately: true);

  Future<List<TodayTaskContext>> getNextTasksForGoal(
    String goalUid, {
    int limit = 3,
  }) async {
    if (goalUid.isEmpty) return [];
    final goal = await _db.goals
        .filter()
        .uidEqualTo(goalUid)
        .deletedAtIsNull()
        .findFirst();
    if (goal == null) return [];

    final tasks = await _db.tasks
        .filter()
        .deletedAtIsNull()
        .isCompletedEqualTo(false)
        .findAll()
      ..sort(_compareUrgency);
    final contexts = await _toContexts(tasks);
    return contexts
        .where((ctx) => ctx.goal?.id == goal.id)
        .take(limit)
        .toList();
  }

  Future<List<Task>> getAll() =>
      _db.tasks.filter().deletedAtIsNull().build().findAll();

  Future<List<TodayTaskContext>> getActiveTaskContexts() async {
    final tasks = await _db.tasks
        .filter()
        .deletedAtIsNull()
        .isCompletedEqualTo(false)
        .findAll()
      ..sort(_compareByDueDate);
    final contexts = await _toContexts(tasks);
    return contexts.where((ctx) => ctx.goal?.isArchived != true).toList();
  }

  Future<List<TodayTaskContext>> getFocusTasks(int goalId) async {
    final tasks = await _db.tasks
        .filter()
        .deletedAtIsNull()
        .isCompletedEqualTo(false)
        .findAll()
      ..sort(_compareUrgency);
    final contexts = await _toContexts(tasks);
    return contexts.where((ctx) => ctx.goal?.id == goalId).take(5).toList();
  }

  /// Priority desc, then due date with undated tasks LAST (Isar's
  /// sortByDueDate puts nulls first, ranking undated tasks above urgent
  /// dated ones), then manual sort order.
  static int _compareUrgency(Task a, Task b) {
    final byPriority = b.priority.compareTo(a.priority);
    if (byPriority != 0) return byPriority;
    final byDue = _compareDueDatesNullsLast(a.dueDate, b.dueDate);
    if (byDue != 0) return byDue;
    return a.sortOrder.compareTo(b.sortOrder);
  }

  static int _compareByDueDate(Task a, Task b) {
    final byDue = _compareDueDatesNullsLast(a.dueDate, b.dueDate);
    if (byDue != 0) return byDue;
    return a.sortOrder.compareTo(b.sortOrder);
  }

  static int _compareDueDatesNullsLast(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
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

    final now = DateTime.now();
    final task = Task()
      ..uid = _uuid.v4()
      ..text = text
      ..isCompleted = false
      ..dueDate = dueDate
      ..priority = priority
      ..note = note
      ..createdAt = now
      ..completedAt = null
      ..sortOrder = await _nextSortOrder(milestoneId)
      // Kept alongside the link so the row is self-describing on the wire.
      ..milestoneUid = ms.uid
      ..updatedAt = now;
    task.milestone.value = ms;

    await _db.writeTxn(() async {
      await _db.tasks.put(task);
      await task.milestone.save();
    });
    await LocalChanges.instance.notify();
    return task;
  }

  Future<void> update(Task task) async {
    task.updatedAt = DateTime.now();
    await _db.writeTxn(() async {
      await _db.tasks.put(task);
    });
    await LocalChanges.instance.notify();
  }

  Future<void> setDueDate(int taskId, DateTime? dueDate) async {
    final task = await getById(taskId);
    if (task == null) return;
    task.dueDate = dueDate;
    task.updatedAt = DateTime.now();
    await _db.writeTxn(() async => _db.tasks.put(task));
    await LocalChanges.instance.notify();
  }

  Future<void> setDueDates(List<int> taskIds, DateTime? dueDate) async {
    if (taskIds.isEmpty) return;
    final now = DateTime.now();
    await _db.writeTxn(() async {
      for (final id in taskIds) {
        final task = await _db.tasks.get(id);
        if (task != null && task.deletedAt == null) {
          task.dueDate = dueDate;
          task.updatedAt = now;
          await _db.tasks.put(task);
        }
      }
    });
    await LocalChanges.instance.notify();
  }

  Future<void> toggleComplete(int id) async {
    final task = await getById(id);
    if (task == null) return;
    final now = DateTime.now();
    task.isCompleted = !task.isCompleted;
    task.completedAt = task.isCompleted ? now : null;
    task.updatedAt = now;
    await _db.writeTxn(() async => _db.tasks.put(task));
    await LocalChanges.instance.notify();
  }

  Future<void> delete(int id) async {
    final task = await getById(id);
    if (task == null) return;
    final now = DateTime.now();
    task.deletedAt = now;
    task.updatedAt = now;
    await _db.writeTxn(() async => _db.tasks.put(task));
    await LocalChanges.instance.notify();
  }

  Future<void> reorder(List<Task> tasks) async {
    final now = DateTime.now();
    await _db.writeTxn(() async {
      for (int i = 0; i < tasks.length; i++) {
        if (tasks[i].sortOrder == i) continue;
        tasks[i].sortOrder = i;
        tasks[i].updatedAt = now;
      }
      await _db.tasks.putAll(tasks);
    });
    await LocalChanges.instance.notify();
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
      if (milestone?.deletedAt != null) continue;
      Goal? goal;
      if (milestone != null) {
        await milestone.goal.load();
        goal = milestone.goal.value;
        if (goal?.deletedAt != null) continue;
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
