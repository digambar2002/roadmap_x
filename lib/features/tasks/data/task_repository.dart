import 'package:isar_community/isar.dart';
import 'package:uuid/uuid.dart';
import '../../../core/db/isar_service.dart';
import '../../../core/models/models.dart';
import '../../../core/services/local_changes.dart';
import '../../../core/models/today_task.dart';
import '../../../core/services/sound_service.dart';
import '../domain/repeat_rule.dart';

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
  /// Creates a task. With no [milestoneId] it goes to the Inbox: quick
  /// capture should never require choosing a goal first.
  Future<Task> create({
    int? milestoneId,
    required String text,
    int priority = 0,
    DateTime? dueDate,
    String? note,
    String? repeat,
  }) async {
    Milestone? ms;
    if (milestoneId != null) {
      ms = await _db.milestones.get(milestoneId);
      if (ms == null || ms.deletedAt != null) {
        throw StateError('Milestone not found: $milestoneId');
      }
    }

    final now = DateTime.now();
    final task = Task()
      ..uid = _uuid.v4()
      ..text = text
      ..isCompleted = false
      ..dueDate = dueDate
      ..priority = priority
      ..note = note
      ..repeat = repeat
      ..createdAt = now
      ..completedAt = null
      ..sortOrder = ms == null ? 0 : await _nextSortOrder(ms.id)
      // Kept alongside the link so the row is self-describing on the wire.
      ..milestoneUid = ms?.uid ?? ''
      ..updatedAt = now;
    if (ms != null) task.milestone.value = ms;

    await _db.writeTxn(() async {
      await _db.tasks.put(task);
      if (ms != null) await task.milestone.save();
    });
    await LocalChanges.instance.notify();
    return task;
  }

  /// Moves a task into a milestone, or back to the Inbox with null.
  Future<void> moveToMilestone(int taskId, int? milestoneId) async {
    final task = await getById(taskId);
    if (task == null) return;
    Milestone? ms;
    if (milestoneId != null) {
      ms = await _db.milestones.get(milestoneId);
      if (ms == null || ms.deletedAt != null) {
        throw StateError('Milestone not found: $milestoneId');
      }
    }
    task
      ..milestoneUid = ms?.uid ?? ''
      ..sortOrder = ms == null ? 0 : await _nextSortOrder(ms.id)
      ..updatedAt = DateTime.now();
    task.milestone.value = ms;
    await _db.writeTxn(() async {
      await _db.tasks.put(task);
      await task.milestone.save();
    });
    await LocalChanges.instance.notify();
  }

  /// Tasks by uid, in the order given; missing or deleted ones are left out.
  Future<List<Task>> getByUids(List<String> uids) async {
    final out = <Task>[];
    for (final uid in uids) {
      final t = await _db.tasks
          .filter()
          .uidEqualTo(uid)
          .deletedAtIsNull()
          .findFirst();
      if (t != null) out.add(t);
    }
    return out;
  }

  /// Open tasks that belong to no goal yet.
  Future<List<Task>> getInbox() async {
    final tasks = await _db.tasks
        .filter()
        .deletedAtIsNull()
        .isCompletedEqualTo(false)
        .milestoneUidEqualTo('')
        .findAll();
    tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return tasks;
  }

  /// Applies the editable fields of [edited] onto the current row.
  ///
  /// The edit sheet holds the object it was opened with; writing that back
  /// whole would undo anything that changed meanwhile (a completion from the
  /// home-screen widget, a sync merge). Completion is only ever promoted here,
  /// never reverted: un-completing goes through [toggle].
  Future<void> update(Task edited) async {
    final fresh = await getById(edited.id) ?? edited;
    fresh
      ..text = edited.text
      ..priority = edited.priority
      ..dueDate = edited.dueDate
      ..note = edited.note
      ..repeat = edited.repeat;
    if (edited.isCompleted && !fresh.isCompleted) {
      fresh
        ..isCompleted = true
        ..completedAt = edited.completedAt ?? DateTime.now();
    }
    fresh.updatedAt = DateTime.now();
    await _db.writeTxn(() async {
      await _db.tasks.put(fresh);
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

  /// [silent] for completions that did not come from a tap in the app,
  /// such as ones queued by the home-screen widget.
  Future<void> toggleComplete(int id, {bool silent = false}) async {
    final task = await getById(id);
    if (task == null) return;
    final now = DateTime.now();
    task.isCompleted = !task.isCompleted;
    task.completedAt = task.isCompleted ? now : null;
    task.updatedAt = now;

    // Repeating tasks: completing one schedules the next occurrence, and
    // un-completing it removes that occurrence again, so a mis-tap never
    // leaves a duplicate behind. The completed row stays as history (and
    // keeps counting for XP).
    final rule = parseRepeatRule(task.repeat);
    Task? next;
    Task? undo;
    if (rule != null) {
      final base = task.dueDate ?? DateTime(now.year, now.month, now.day);
      final nextDue = rule.next(base);
      final sibling = await _openOccurrence(task, nextDue);
      if (task.isCompleted && sibling == null) {
        next = Task()
          ..uid = _uuid.v4()
          ..text = task.text
          ..isCompleted = false
          ..dueDate = nextDue
          ..priority = task.priority
          ..note = task.note
          ..repeat = task.repeat
          ..createdAt = now
          ..completedAt = null
          ..sortOrder = task.sortOrder
          ..milestoneUid = task.milestoneUid
          ..updatedAt = now;
        await task.milestone.load();
        if (task.milestone.value != null) {
          next.milestone.value = task.milestone.value;
        }
      } else if (!task.isCompleted && sibling != null) {
        undo = sibling
          ..deletedAt = now
          ..updatedAt = now;
      }
    }

    await _db.writeTxn(() async {
      await _db.tasks.put(task);
      if (next != null) {
        await _db.tasks.put(next);
        await next.milestone.save();
      }
      if (undo != null) await _db.tasks.put(undo);
    });
    if (task.isCompleted && !silent) SoundService.instance.play(Sfx.done);
    await LocalChanges.instance.notify();
  }

  /// The not-yet-done next occurrence of a repeating [task], if any.
  Future<Task?> _openOccurrence(Task task, DateTime due) async {
    final candidates = await _db.tasks
        .filter()
        .deletedAtIsNull()
        .isCompletedEqualTo(false)
        .milestoneUidEqualTo(task.milestoneUid)
        .textEqualTo(task.text)
        .repeatEqualTo(task.repeat)
        .findAll();
    for (final c in candidates) {
      if (c.id != task.id && c.dueDate != null && _sameDay(c.dueDate!, due)) {
        return c;
      }
    }
    return null;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

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
