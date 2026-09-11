import 'package:isar_community/isar.dart';

import '../db/isar_service.dart';
import '../models/models.dart';
import 'local_changes.dart';

/// Daily non-negotiables, stored one row per (day, checkbox).
///
/// This used to be a JSON array in SharedPreferences keyed by day. That shape
/// cannot survive multi-device sync: two devices ticking different boxes on
/// the same day both rewrite the whole day's array, and whichever lands second
/// erases the other's tick. Per-checkbox rows make those writes independent.
class HabitCheckinService {
  HabitCheckinService._();
  static final HabitCheckinService instance = HabitCheckinService._();

  static const int checkCount = 4;

  Isar get _db => IsarService.instance.db;

  static String dayKeyFor(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<List<bool>> getChecksForDate(DateTime date) async {
    final rows = await _db.habitCheckins
        .filter()
        .dayKeyEqualTo(dayKeyFor(date))
        .deletedAtIsNull()
        .findAll();

    final checks = List<bool>.filled(checkCount, false);
    for (final row in rows) {
      if (row.checkIndex < 0 || row.checkIndex >= checkCount) continue;
      checks[row.checkIndex] = row.isChecked;
    }
    return checks;
  }

  Future<void> setCheckForDate(DateTime date, int index, bool value) async {
    if (index < 0 || index >= checkCount) return;
    final dayKey = dayKeyFor(date);
    final uid = HabitCheckin.uidFor(dayKey, index);

    // Unticking keeps the row and flips the flag rather than deleting it.
    // A value change carries its own updatedAt, so last-writer-wins resolves
    // it without needing a tombstone.
    final existing =
        await _db.habitCheckins.filter().uidEqualTo(uid).findFirst();
    final row = existing ?? (HabitCheckin()..uid = uid);
    row
      ..dayKey = dayKey
      ..checkIndex = index
      ..isChecked = value
      ..deletedAt = null
      ..updatedAt = DateTime.now();

    await _db.writeTxn(() async => _db.habitCheckins.put(row));
    await LocalChanges.instance.notify();
  }

  Future<bool> isDayComplete(DateTime date) async {
    final checks = await getChecksForDate(date);
    return checks.every((entry) => entry);
  }

  /// Days on which every non-negotiable was ticked.
  ///
  /// Reads the whole table once and groups in memory. The previous
  /// implementation issued one lookup per day, which meant 3650 reads to
  /// compute a streak.
  Future<Set<String>> _completeDayKeys() async {
    final rows = await _db.habitCheckins
        .filter()
        .deletedAtIsNull()
        .isCheckedEqualTo(true)
        .findAll();

    final ticksPerDay = <String, Set<int>>{};
    for (final row in rows) {
      if (row.checkIndex < 0 || row.checkIndex >= checkCount) continue;
      ticksPerDay.putIfAbsent(row.dayKey, () => <int>{}).add(row.checkIndex);
    }
    return ticksPerDay.entries
        .where((entry) => entry.value.length == checkCount)
        .map((entry) => entry.key)
        .toSet();
  }

  Future<int> getCurrentStreak() async {
    final complete = await _completeDayKeys();
    if (complete.isEmpty) return 0;

    final now = DateTime.now();
    var streak = 0;
    // An incomplete "today" doesn't break the streak — the day isn't over
    // yet. Otherwise a long streak would read 0 every morning until all of
    // today's checks were done.
    for (var i = 0; i < 3650; i++) {
      final day = DateTime(now.year, now.month, now.day - i);
      if (complete.contains(dayKeyFor(day))) {
        streak++;
      } else if (i == 0) {
        continue;
      } else {
        break;
      }
    }
    return streak;
  }

  Future<Set<DateTime>> getCompleteDates({int lastDays = 365}) async {
    final complete = await _completeDayKeys();
    final now = DateTime.now();
    final cutoff = DateTime(now.year, now.month, now.day - (lastDays - 1));

    final dates = <DateTime>{};
    for (final key in complete) {
      final day = DateTime.tryParse(key);
      if (day == null) continue;
      if (day.isBefore(cutoff)) continue;
      dates.add(day);
    }
    return dates;
  }

  /// Fires on any check-in change, including ones merged in from another
  /// device, so the UI repaints when a sync lands.
  Stream<void> watchActivity() =>
      _db.habitCheckins.watchLazy(fireImmediately: true);
}
