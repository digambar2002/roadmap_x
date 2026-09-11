import 'package:isar_community/isar.dart';
import 'package:uuid/uuid.dart';
import '../../../core/db/isar_service.dart';
import '../../../core/models/models.dart';
import '../../../core/services/local_changes.dart';

class GoalRepository {
  GoalRepository._();
  static final GoalRepository instance = GoalRepository._();

  Isar get _db => IsarService.instance.db;
  static const _uuid = Uuid();

  // ── Streams ──────────────────────────────────────────────
  // Every read filters tombstones: deleted rows stay in the table so peers
  // learn about the delete, but they must be invisible to the UI.
  Stream<List<Goal>> watchAll() => _db.goals
      .filter()
      .deletedAtIsNull()
      .sortBySortOrder()
      .build()
      .watch(fireImmediately: true);

  Stream<List<Goal>> watchActive() => _db.goals
      .filter()
      .deletedAtIsNull()
      .isArchivedEqualTo(false)
      .sortBySortOrder()
      .build()
      .watch(fireImmediately: true);

  Stream<Goal?> watchById(int id) => _db.goals
      .watchObject(id, fireImmediately: true)
      .map((goal) => goal?.deletedAt == null ? goal : null);

  // ── Reads ─────────────────────────────────────────────────
  Future<List<Goal>> getAll() =>
      _db.goals.filter().deletedAtIsNull().sortBySortOrder().build().findAll();

  Future<Goal?> getById(int id) async {
    final goal = await _db.goals.get(id);
    return goal?.deletedAt == null ? goal : null;
  }

  Future<Goal?> getByUid(String uid) =>
      _db.goals.filter().uidEqualTo(uid).deletedAtIsNull().findFirst();

  /// Active goals with the highest priority first, then manual order.
  ///
  /// Isar cannot sort descending on one field and ascending on another in a
  /// single query, so the ordering is finished in Dart.
  Stream<List<Goal>> watchActiveByPriority() =>
      watchActive().map(sortByPriority);

  /// Sorts a goal list Focus → Active → Someday, preserving manual order
  /// inside each band.
  static List<Goal> sortByPriority(List<Goal> goals) {
    final sorted = [...goals];
    sorted.sort((a, b) {
      final byPriority = b.priority.compareTo(a.priority);
      if (byPriority != 0) return byPriority;
      return a.sortOrder.compareTo(b.sortOrder);
    });
    return sorted;
  }

  /// Live count of non-archived goals, for the free-tier goal cap.
  Stream<int> watchActiveCount() => _db.goals
      .filter()
      .deletedAtIsNull()
      .isArchivedEqualTo(false)
      .build()
      .watch(fireImmediately: true)
      .map((goals) => goals.length);

  Future<int> activeCount() =>
      _db.goals.filter().deletedAtIsNull().isArchivedEqualTo(false).count();

  // ── Writes ────────────────────────────────────────────────
  Future<Goal> create({
    required String name,
    required String description,
    required String emoji,
    required int colorHex,
    required DateTime targetDate,
    int priority = GoalPriority.active,
  }) async {
    final now = DateTime.now();
    final goal = Goal()
      ..uid = _uuid.v4()
      ..name = name
      ..description = description
      ..emoji = emoji
      ..colorHex = colorHex
      ..createdAt = now
      ..targetDate = targetDate
      ..isArchived = false
      ..sortOrder = await _nextSortOrder()
      ..priority = GoalPriority.clamp(priority)
      ..updatedAt = now;

    await _db.writeTxn(() async {
      await _db.goals.put(goal);
    });
    await LocalChanges.instance.notify();
    return goal;
  }

  Future<void> update(Goal goal) async {
    goal.updatedAt = DateTime.now();
    await _db.writeTxn(() async {
      await _db.goals.put(goal);
    });
    await LocalChanges.instance.notify();
  }

  Future<void> archive(int id) async {
    final goal = await getById(id);
    if (goal == null) return;
    goal.isArchived = true;
    goal.updatedAt = DateTime.now();
    await _db.writeTxn(() async => _db.goals.put(goal));
    await LocalChanges.instance.notify();
  }

  Future<void> unarchive(int id) async {
    final goal = await getById(id);
    if (goal == null) return;
    goal.isArchived = false;
    goal.updatedAt = DateTime.now();
    await _db.writeTxn(() async => _db.goals.put(goal));
    await LocalChanges.instance.notify();
  }

  /// Soft delete, cascading to milestones and tasks.
  ///
  /// The children need their own tombstones rather than being dropped: a peer
  /// that already has them would otherwise keep them as orphans, since it
  /// never hears that they went away.
  Future<void> delete(int id) async {
    final goal = await getById(id);
    if (goal == null) return;
    final now = DateTime.now();

    await goal.milestones.load();
    final milestones =
        goal.milestones.where((m) => m.deletedAt == null).toList();

    final tasks = <Task>[];
    for (final milestone in milestones) {
      await milestone.tasks.load();
      tasks.addAll(milestone.tasks.where((t) => t.deletedAt == null));
    }

    // Unlink schedule items that point at this goal so they don't keep a
    // dangling uid (losing their color/name/linked tasks silently).
    final linkedScheduleItems = await _db.scheduleItems
        .filter()
        .goalUidEqualTo(goal.uid)
        .deletedAtIsNull()
        .findAll();
    for (final item in linkedScheduleItems) {
      item.goalUid = '';
      item.updatedAt = now;
    }

    for (final task in tasks) {
      task.deletedAt = now;
      task.updatedAt = now;
    }
    for (final milestone in milestones) {
      milestone.deletedAt = now;
      milestone.updatedAt = now;
    }
    goal.deletedAt = now;
    goal.updatedAt = now;

    await _db.writeTxn(() async {
      await _db.tasks.putAll(tasks);
      await _db.milestones.putAll(milestones);
      await _db.scheduleItems.putAll(linkedScheduleItems);
      await _db.goals.put(goal);
    });
    await LocalChanges.instance.notify();
  }

  /// Reorder goals. [orderedVisible] may be a filtered subset (e.g. only
  /// active goals): the reordered goals are placed back into the position
  /// slots they occupied, so hidden goals keep their relative order instead
  /// of getting colliding sortOrders.
  Future<void> reorder(List<Goal> orderedVisible) async {
    final all = await getAll();
    final visibleIds = orderedVisible.map((g) => g.id).toSet();
    var nextVisible = 0;
    final merged = <Goal>[
      for (final g in all)
        visibleIds.contains(g.id) ? orderedVisible[nextVisible++] : g,
    ];
    final now = DateTime.now();
    await _db.writeTxn(() async {
      for (int i = 0; i < merged.length; i++) {
        if (merged[i].sortOrder == i) continue;
        merged[i].sortOrder = i;
        merged[i].updatedAt = now;
      }
      await _db.goals.putAll(merged);
    });
    await LocalChanges.instance.notify();
  }

  /// Deleted rows are included so a sortOrder is never handed out twice.
  Future<int> _nextSortOrder() async {
    final last =
        await _db.goals.where().sortBySortOrderDesc().limit(1).findFirst();
    return (last?.sortOrder ?? -1) + 1;
  }
}
