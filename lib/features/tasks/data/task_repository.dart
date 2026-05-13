import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';
import '../../../core/db/isar_service.dart';
import '../../../core/models/models.dart';

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
    return task;
  }

  Future<void> update(Task task) async {
    await _db.writeTxn(() async {
      await _db.tasks.put(task);
    });
  }

  Future<void> toggleComplete(int id) async {
    final task = await _db.tasks.get(id);
    if (task == null) return;
    task.isCompleted = !task.isCompleted;
    task.completedAt = task.isCompleted ? DateTime.now() : null;
    await _db.writeTxn(() async => _db.tasks.put(task));
  }

  Future<void> delete(int id) async {
    await _db.writeTxn(() async => _db.tasks.delete(id));
  }

  Future<void> reorder(List<Task> tasks) async {
    await _db.writeTxn(() async {
      for (int i = 0; i < tasks.length; i++) {
        tasks[i].sortOrder = i;
      }
      await _db.tasks.putAll(tasks);
    });
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
}
