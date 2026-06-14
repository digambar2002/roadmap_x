import 'package:isar_community/isar.dart';
import 'package:uuid/uuid.dart';
import '../../../core/db/isar_service.dart';
import '../../../core/models/models.dart';
import '../../../core/services/backup_service.dart';

class GoalRepository {
  GoalRepository._();
  static final GoalRepository instance = GoalRepository._();

  Isar get _db => IsarService.instance.db;
  static const _uuid = Uuid();

  // ── Streams ──────────────────────────────────────────────
  Stream<List<Goal>> watchAll() =>
      _db.goals.where().sortBySortOrder().build().watch(fireImmediately: true);

  Stream<List<Goal>> watchActive() => _db.goals
      .filter()
      .isArchivedEqualTo(false)
      .sortBySortOrder()
      .build()
      .watch(fireImmediately: true);

  Stream<Goal?> watchById(int id) =>
      _db.goals.watchObject(id, fireImmediately: true);

  // ── Reads ─────────────────────────────────────────────────
  Future<List<Goal>> getAll() =>
      _db.goals.where().sortBySortOrder().build().findAll();

  Future<Goal?> getById(int id) => _db.goals.get(id);
  Future<Goal?> getByUid(String uid) =>
      _db.goals.filter().uidEqualTo(uid).findFirst();

  // ── Writes ────────────────────────────────────────────────
  Future<Goal> create({
    required String name,
    required String description,
    required String emoji,
    required int colorHex,
    required DateTime targetDate,
  }) async {
    final goal = Goal()
      ..uid = _uuid.v4()
      ..name = name
      ..description = description
      ..emoji = emoji
      ..colorHex = colorHex
      ..createdAt = DateTime.now()
      ..targetDate = targetDate
      ..isArchived = false
      ..sortOrder = await _nextSortOrder();

    await _db.writeTxn(() async {
      await _db.goals.put(goal);
    });
    await BackupService.instance.scheduleBackup();
    return goal;
  }

  Future<void> update(Goal goal) async {
    await _db.writeTxn(() async {
      await _db.goals.put(goal);
    });
    await BackupService.instance.scheduleBackup();
  }

  Future<void> archive(int id) async {
    final goal = await _db.goals.get(id);
    if (goal == null) return;
    goal.isArchived = true;
    await _db.writeTxn(() async => _db.goals.put(goal));
    await BackupService.instance.scheduleBackup();
  }

  Future<void> unarchive(int id) async {
    final goal = await _db.goals.get(id);
    if (goal == null) return;
    goal.isArchived = false;
    await _db.writeTxn(() async => _db.goals.put(goal));
    await BackupService.instance.scheduleBackup();
  }

  Future<void> delete(int id) async {
    final goal = await _db.goals.get(id);
    if (goal == null) return;

    // Load milestones and tasks via links
    await goal.milestones.load();
    final milestoneIds = goal.milestones.map((m) => m.id).toList();

    final taskIds = <int>[];
    for (final m in goal.milestones) {
      await m.tasks.load();
      taskIds.addAll(m.tasks.map((t) => t.id));
    }

    await _db.writeTxn(() async {
      await _db.tasks.deleteAll(taskIds);
      await _db.milestones.deleteAll(milestoneIds);
      await _db.goals.delete(id);
    });
    await BackupService.instance.scheduleBackup();
  }

  Future<void> reorder(List<Goal> goals) async {
    await _db.writeTxn(() async {
      for (int i = 0; i < goals.length; i++) {
        goals[i].sortOrder = i;
      }
      await _db.goals.putAll(goals);
    });
    await BackupService.instance.scheduleBackup();
  }

  Future<int> _nextSortOrder() async {
    final last =
        await _db.goals.where().sortBySortOrderDesc().limit(1).findFirst();
    return (last?.sortOrder ?? -1) + 1;
  }
}
