import 'package:isar_community/isar.dart';

import '../db/isar_service.dart';
import '../models/models.dart';
import 'local_changes.dart';

/// Per-day completion of schedule blocks, stored one row per
/// (day, schedule block) — see [HabitCheckinService] for why the old
/// SharedPreferences-blob shape could not be synced without losing writes.
class ScheduleCompletionService {
  ScheduleCompletionService._();
  static final ScheduleCompletionService instance =
      ScheduleCompletionService._();

  Isar get _db => IsarService.instance.db;

  static String dayKeyFor(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<Set<String>> getCompletedForDate(DateTime date) async {
    final rows = await _db.scheduleCompletions
        .filter()
        .dayKeyEqualTo(dayKeyFor(date))
        .deletedAtIsNull()
        .isCompletedEqualTo(true)
        .findAll();
    return rows.map((row) => row.scheduleUid).toSet();
  }

  Future<bool> isCompleted(DateTime date, String scheduleUid) async {
    final row = await _db.scheduleCompletions
        .filter()
        .uidEqualTo(ScheduleCompletion.uidFor(dayKeyFor(date), scheduleUid))
        .deletedAtIsNull()
        .findFirst();
    return row?.isCompleted ?? false;
  }

  Future<void> setCompleted(
    DateTime date,
    String scheduleUid,
    bool completed,
  ) async {
    final dayKey = dayKeyFor(date);
    final uid = ScheduleCompletion.uidFor(dayKey, scheduleUid);

    final existing =
        await _db.scheduleCompletions.filter().uidEqualTo(uid).findFirst();
    final row = existing ?? (ScheduleCompletion()..uid = uid);
    row
      ..dayKey = dayKey
      ..scheduleUid = scheduleUid
      ..isCompleted = completed
      ..deletedAt = null
      ..updatedAt = DateTime.now();

    await _db.writeTxn(() async => _db.scheduleCompletions.put(row));
    await LocalChanges.instance.notify();
  }

  /// Dates with at least one schedule block marked done.
  Future<Set<DateTime>> getCompletedDates({int lastDays = 365}) async {
    final rows = await _db.scheduleCompletions
        .filter()
        .deletedAtIsNull()
        .isCompletedEqualTo(true)
        .findAll();

    final now = DateTime.now();
    // lastDays days including today; date-component math avoids the DST
    // drift of Duration subtraction and the previous off-by-one
    // (which included lastDays + 1 days).
    final cutoff = DateTime(now.year, now.month, now.day - (lastDays - 1));

    final dates = <DateTime>{};
    for (final row in rows) {
      final day = DateTime.tryParse(row.dayKey);
      if (day == null) continue;
      if (day.isBefore(cutoff)) continue;
      dates.add(day);
    }
    return dates;
  }

  Future<int> completedCountOnDate(DateTime date) async {
    final done = await getCompletedForDate(date);
    return done.length;
  }

  /// Fires on any completion change, including ones merged in from another
  /// device, so the UI repaints when a sync lands.
  Stream<void> watchActivity() =>
      _db.scheduleCompletions.watchLazy(fireImmediately: true);
}
