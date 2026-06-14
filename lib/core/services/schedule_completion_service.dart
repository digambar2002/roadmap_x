import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'backup_service.dart';

class ScheduleCompletionService {
  ScheduleCompletionService._();
  static final ScheduleCompletionService instance =
      ScheduleCompletionService._();

  static const _prefix = 'schedule_completion_';

  String _dayKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _key(DateTime date) => '$_prefix${_dayKey(date)}';

  Future<Set<String>> getCompletedForDate(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(date));
    if (raw == null || raw.isEmpty) return <String>{};
    final list = (jsonDecode(raw) as List).cast<String>();
    return list.toSet();
  }

  Future<bool> isCompleted(DateTime date, String scheduleUid) async {
    final done = await getCompletedForDate(date);
    return done.contains(scheduleUid);
  }

  Future<void> setCompleted(
    DateTime date,
    String scheduleUid,
    bool completed,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final done = await getCompletedForDate(date);
    if (completed) {
      done.add(scheduleUid);
    } else {
      done.remove(scheduleUid);
    }
    await prefs.setString(_key(date), jsonEncode(done.toList()));
    await BackupService.instance.scheduleBackup();
  }

  /// Dates with at least one schedule block marked done.
  Future<Set<DateTime>> getCompletedDates({int lastDays = 365}) async {
    final prefs = await SharedPreferences.getInstance();
    final dates = <DateTime>{};
    final now = DateTime.now();
    final cutoff = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: lastDays));

    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) continue;
      try {
        final list = (jsonDecode(raw) as List);
        if (list.isEmpty) continue;
        final datePart = key.substring(_prefix.length);
        final day = DateTime.parse(datePart);
        if (!day.isBefore(cutoff)) dates.add(day);
      } catch (_) {
        continue;
      }
    }
    return dates;
  }

  Future<int> completedCountOnDate(DateTime date) async {
    final done = await getCompletedForDate(date);
    return done.length;
  }
}
