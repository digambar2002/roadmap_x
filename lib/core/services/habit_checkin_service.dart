import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'backup_service.dart';

class HabitCheckinService {
  HabitCheckinService._();
  static final HabitCheckinService instance = HabitCheckinService._();

  static const int checkCount = 4;
  static const String _checksPrefix = 'habit_checks_';

  String _dayKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<List<bool>> getChecksForDate(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_checksPrefix${_dayKey(date)}');
    if (raw == null || raw.isEmpty) return List<bool>.filled(checkCount, false);
    final parsed = (jsonDecode(raw) as List).map(_parseBool).toList();
    if (parsed.length < checkCount) {
      parsed.addAll(List<bool>.filled(checkCount - parsed.length, false));
    }
    return parsed.take(checkCount).toList();
  }

  Future<void> setCheckForDate(DateTime date, int index, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final checks = await getChecksForDate(date);
    checks[index] = value;
    await prefs.setString(
      '$_checksPrefix${_dayKey(date)}',
      jsonEncode(checks),
    );
    await BackupService.instance.scheduleBackup();
  }

  Future<bool> isDayComplete(DateTime date) async {
    final checks = await getChecksForDate(date);
    return checks.every((entry) => entry);
  }

  Future<int> getCurrentStreak() async {
    final now = DateTime.now();
    var streak = 0;
    for (var i = 0; i < 3650; i++) {
      final day = DateTime(now.year, now.month, now.day - i);
      final complete = await isDayComplete(day);
      if (!complete) break;
      streak++;
    }
    return streak;
  }

  /// Dates where all non-negotiables were completed.
  bool _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is int) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1';
    }
    return false;
  }

  Future<Set<DateTime>> getCompleteDates({int lastDays = 365}) async {
    final dates = <DateTime>{};
    final now = DateTime.now();
    for (var i = 0; i < lastDays; i++) {
      final day = DateTime(now.year, now.month, now.day - i);
      if (await isDayComplete(day)) dates.add(day);
    }
    return dates;
  }
}
