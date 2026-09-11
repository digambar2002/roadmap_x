import 'package:isar_community/isar.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/isar_service.dart';
import '../../../core/models/habit_icons.dart';
import '../../../core/models/models.dart';
import '../../../core/services/local_changes.dart';

class HabitRepository {
  HabitRepository._();
  static final HabitRepository instance = HabitRepository._();

  Isar get _db => IsarService.instance.db;
  static const _uuid = Uuid();

  /// What a brand new install starts with, so the dashboard is not empty.
  static const List<({String label, String iconKey})> starterHabits = [
    (label: 'Morning workout', iconKey: 'gym'),
    (label: 'Deep work block', iconKey: 'focus'),
    (label: 'Read 20 pages', iconKey: 'read'),
    (label: 'Evening review', iconKey: 'write'),
  ];

  // ── Reads ─────────────────────────────────────────────────
  Stream<List<Habit>> watchAll() => _db.habits
      .filter()
      .deletedAtIsNull()
      .sortBySortOrder()
      .build()
      .watch(fireImmediately: true);

  Future<List<Habit>> getAll() => _db.habits
      .filter()
      .deletedAtIsNull()
      .sortBySortOrder()
      .build()
      .findAll();

  Future<int> count() => _db.habits.filter().deletedAtIsNull().count();

  // ── Writes ────────────────────────────────────────────────
  Future<Habit> create({
    required String label,
    required String iconKey,
  }) async {
    final now = DateTime.now();
    final habit = Habit()
      ..uid = _uuid.v4()
      ..label = label
      ..iconKey = HabitIcons.catalog.containsKey(iconKey)
          ? iconKey
          : HabitIcons.fallbackKey
      ..sortOrder = await _nextSortOrder()
      // Dated to today so it is not expected on days already past.
      ..createdAt = DateTime(now.year, now.month, now.day)
      ..updatedAt = now;

    await _db.writeTxn(() async => _db.habits.put(habit));
    await LocalChanges.instance.notify();
    return habit;
  }

  Future<void> update(Habit habit) async {
    habit.updatedAt = DateTime.now();
    await _db.writeTxn(() async => _db.habits.put(habit));
    await LocalChanges.instance.notify();
  }

  /// Soft delete. The habit's past check-ins are deliberately left alone: they
  /// are a record of what happened, and a peer still needs the tombstone.
  Future<void> delete(int id) async {
    final habit = await _db.habits.get(id);
    if (habit == null || habit.deletedAt != null) return;
    final now = DateTime.now();
    habit
      ..deletedAt = now
      ..updatedAt = now;
    await _db.writeTxn(() async => _db.habits.put(habit));
    await LocalChanges.instance.notify();
  }

  Future<void> reorder(List<Habit> ordered) async {
    final now = DateTime.now();
    await _db.writeTxn(() async {
      for (var i = 0; i < ordered.length; i++) {
        if (ordered[i].sortOrder == i) continue;
        ordered[i].sortOrder = i;
        ordered[i].updatedAt = now;
      }
      await _db.habits.putAll(ordered);
    });
    await LocalChanges.instance.notify();
  }

  /// Deleted rows are included so a sortOrder is never handed out twice.
  Future<int> _nextSortOrder() async {
    final last =
        await _db.habits.where().sortBySortOrderDesc().limit(1).findFirst();
    return (last?.sortOrder ?? -1) + 1;
  }
}
