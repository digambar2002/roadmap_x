import 'package:isar_community/isar.dart';

import '../db/isar_service.dart';
import '../models/models.dart';
import 'local_changes.dart';

/// Daily non-negotiables, stored one row per (day, habit).
///
/// Habits used to be four fixed slots; they are now [Habit] rows the user
/// controls, so check-ins are keyed by habit uid rather than by position. A
/// positional key would silently re-point every past tick the moment someone
/// reordered or deleted a habit.
class HabitCheckinService {
  HabitCheckinService._();
  static final HabitCheckinService instance = HabitCheckinService._();

  Isar get _db => IsarService.instance.db;

  static String dayKeyFor(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static DateTime? parseDayKey(String key) => DateTime.tryParse(key);

  /// Ticked habit uids for [date].
  Future<Set<String>> getCheckedForDate(DateTime date) async {
    final rows = await _db.habitCheckins
        .filter()
        .dayKeyEqualTo(dayKeyFor(date))
        .deletedAtIsNull()
        .isCheckedEqualTo(true)
        .findAll();
    return rows.map((row) => row.habitUid).toSet();
  }

  Future<bool> isChecked(DateTime date, String habitUid) async {
    final row = await _db.habitCheckins
        .filter()
        .uidEqualTo(HabitCheckin.uidFor(dayKeyFor(date), habitUid))
        .deletedAtIsNull()
        .findFirst();
    return row?.isChecked ?? false;
  }

  Future<void> setChecked(
    DateTime date,
    String habitUid,
    bool value,
  ) async {
    if (habitUid.isEmpty) return;
    final dayKey = dayKeyFor(date);
    final uid = HabitCheckin.uidFor(dayKey, habitUid);

    // Unticking keeps the row and flips the flag rather than deleting it. A
    // value change carries its own updatedAt, so last-writer-wins resolves it
    // without needing a tombstone.
    final existing =
        await _db.habitCheckins.filter().uidEqualTo(uid).findFirst();
    final row = existing ?? (HabitCheckin()..uid = uid);
    row
      ..dayKey = dayKey
      ..habitUid = habitUid
      ..isChecked = value
      ..deletedAt = null
      ..updatedAt = DateTime.now();

    await _db.writeTxn(() async => _db.habitCheckins.put(row));
    await LocalChanges.instance.notify();
  }

  /// Habits that were already defined on [day]. A habit added today is not
  /// expected on days before it existed, so adding one cannot retroactively
  /// break a streak.
  static List<Habit> _expectedOn(List<Habit> habits, DateTime day) => habits
      .where((h) => !h.createdAt.isAfter(day))
      .toList();

  Future<bool> isDayComplete(DateTime date) async {
    final habits = await _activeHabits();
    final day = DateTime(date.year, date.month, date.day);
    final expected = _expectedOn(habits, day);
    if (expected.isEmpty) return false;

    final checked = await getCheckedForDate(date);
    return expected.every((h) => checked.contains(h.uid));
  }

  Future<List<Habit>> _activeHabits() => _db.habits
      .filter()
      .deletedAtIsNull()
      .sortBySortOrder()
      .build()
      .findAll();

  /// Days on which every habit then defined was ticked.
  ///
  /// Reads both tables once and groups in memory; the previous implementation
  /// issued one lookup per day, which meant thousands of reads for a streak.
  Future<Set<String>> _completeDayKeys() async {
    final habits = await _activeHabits();
    if (habits.isEmpty) return <String>{};

    final rows = await _db.habitCheckins
        .filter()
        .deletedAtIsNull()
        .isCheckedEqualTo(true)
        .findAll();

    final tickedPerDay = <String, Set<String>>{};
    for (final row in rows) {
      tickedPerDay.putIfAbsent(row.dayKey, () => <String>{}).add(row.habitUid);
    }

    final complete = <String>{};
    for (final entry in tickedPerDay.entries) {
      final day = parseDayKey(entry.key);
      if (day == null) continue;
      final expected = _expectedOn(habits, day);
      if (expected.isEmpty) continue;
      if (expected.every((h) => entry.value.contains(h.uid))) {
        complete.add(entry.key);
      }
    }
    return complete;
  }

  Future<int> getCurrentStreak() async {
    final complete = await _completeDayKeys();
    if (complete.isEmpty) return 0;

    final now = DateTime.now();
    var streak = 0;
    // An incomplete "today" doesn't break the streak — the day isn't over
    // yet. Otherwise a long streak would read 0 every morning until all of
    // today's habits were ticked.
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
      final day = parseDayKey(key);
      if (day == null || day.isBefore(cutoff)) continue;
      dates.add(day);
    }
    return dates;
  }

  /// Fires on any check-in change, including ones merged in from another
  /// device, so the UI repaints when a sync lands.
  Stream<void> watchActivity() =>
      _db.habitCheckins.watchLazy(fireImmediately: true);
}
