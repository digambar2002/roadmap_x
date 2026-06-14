import 'package:isar_community/isar.dart';
import 'package:uuid/uuid.dart';
import '../../../core/db/isar_service.dart';
import '../../../core/models/models.dart';
import '../../../core/services/backup_service.dart';

class MilestoneRepository {
  MilestoneRepository._();
  static final MilestoneRepository instance = MilestoneRepository._();

  Isar get _db => IsarService.instance.db;
  static const _uuid = Uuid();

  // ── Streams ──────────────────────────────────────────────
  Stream<List<Milestone>> watchForGoal(int goalId) => _db.milestones
      .filter()
      .goal((q) => q.idEqualTo(goalId))
      .sortBySortOrder()
      .build()
      .watch(fireImmediately: true);

  // ── Reads ─────────────────────────────────────────────────
  Future<List<Milestone>> getForGoal(int goalId) => _db.milestones
      .filter()
      .goal((q) => q.idEqualTo(goalId))
      .sortBySortOrder()
      .build()
      .findAll();

  Future<Milestone?> getById(int id) => _db.milestones.get(id);

  // ── Writes ────────────────────────────────────────────────
  Future<Milestone> create({
    required int goalId,
    required String title,
    required String theme,
    DateTime? dueDate,
  }) async {
    final goal = await _db.goals.get(goalId);
    if (goal == null) throw Exception('Goal not found: $goalId');

    final ms = Milestone()
      ..uid = _uuid.v4()
      ..title = title
      ..theme = theme
      ..dueDate = dueDate
      ..sortOrder = await _nextSortOrder(goalId)
      ..isCollapsed = false;
    ms.goal.value = goal;

    await _db.writeTxn(() async {
      await _db.milestones.put(ms);
      await ms.goal.save();
    });
    await BackupService.instance.scheduleBackup();
    return ms;
  }

  Future<void> update(Milestone ms) async {
    await _db.writeTxn(() async {
      await _db.milestones.put(ms);
    });
    await BackupService.instance.scheduleBackup();
  }

  Future<void> delete(int id) async {
    final ms = await _db.milestones.get(id);
    if (ms == null) return;
    await ms.tasks.load();
    final taskIds = ms.tasks.map((t) => t.id).toList();

    await _db.writeTxn(() async {
      await _db.tasks.deleteAll(taskIds);
      await _db.milestones.delete(id);
    });
    await BackupService.instance.scheduleBackup();
  }

  Future<void> reorder(List<Milestone> milestones) async {
    await _db.writeTxn(() async {
      for (int i = 0; i < milestones.length; i++) {
        milestones[i].sortOrder = i;
      }
      await _db.milestones.putAll(milestones);
    });
    await BackupService.instance.scheduleBackup();
  }

  Future<int> _nextSortOrder(int goalId) async {
    final last = await _db.milestones
        .filter()
        .goal((q) => q.idEqualTo(goalId))
        .sortBySortOrderDesc()
        .limit(1)
        .findFirst();
    return (last?.sortOrder ?? -1) + 1;
  }
}
