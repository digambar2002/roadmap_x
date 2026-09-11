import 'package:isar_community/isar.dart';
import 'package:uuid/uuid.dart';
import '../../../core/db/isar_service.dart';
import '../../../core/models/models.dart';
import '../../../core/services/local_changes.dart';

class MilestoneRepository {
  MilestoneRepository._();
  static final MilestoneRepository instance = MilestoneRepository._();

  Isar get _db => IsarService.instance.db;
  static const _uuid = Uuid();

  // ── Streams ──────────────────────────────────────────────
  Stream<List<Milestone>> watchForGoal(int goalId) => _db.milestones
      .filter()
      .deletedAtIsNull()
      .goal((q) => q.idEqualTo(goalId))
      .sortBySortOrder()
      .build()
      .watch(fireImmediately: true);

  // ── Reads ─────────────────────────────────────────────────
  Future<List<Milestone>> getForGoal(int goalId) => _db.milestones
      .filter()
      .deletedAtIsNull()
      .goal((q) => q.idEqualTo(goalId))
      .sortBySortOrder()
      .build()
      .findAll();

  Future<Milestone?> getById(int id) async {
    final ms = await _db.milestones.get(id);
    return ms?.deletedAt == null ? ms : null;
  }

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
      ..isCollapsed = false
      // Kept alongside the link so the row is self-describing on the wire.
      ..goalUid = goal.uid
      ..updatedAt = DateTime.now();
    ms.goal.value = goal;

    await _db.writeTxn(() async {
      await _db.milestones.put(ms);
      await ms.goal.save();
    });
    await LocalChanges.instance.notify();
    return ms;
  }

  Future<void> update(Milestone ms) async {
    ms.updatedAt = DateTime.now();
    await _db.writeTxn(() async {
      await _db.milestones.put(ms);
    });
    await LocalChanges.instance.notify();
  }

  /// Soft delete, cascading tombstones to the milestone's tasks.
  Future<void> delete(int id) async {
    final ms = await getById(id);
    if (ms == null) return;
    final now = DateTime.now();

    await ms.tasks.load();
    final tasks = ms.tasks.where((t) => t.deletedAt == null).toList();
    for (final task in tasks) {
      task.deletedAt = now;
      task.updatedAt = now;
    }
    ms.deletedAt = now;
    ms.updatedAt = now;

    await _db.writeTxn(() async {
      await _db.tasks.putAll(tasks);
      await _db.milestones.put(ms);
    });
    await LocalChanges.instance.notify();
  }

  Future<void> reorder(List<Milestone> milestones) async {
    final now = DateTime.now();
    await _db.writeTxn(() async {
      for (int i = 0; i < milestones.length; i++) {
        if (milestones[i].sortOrder == i) continue;
        milestones[i].sortOrder = i;
        milestones[i].updatedAt = now;
      }
      await _db.milestones.putAll(milestones);
    });
    await LocalChanges.instance.notify();
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
