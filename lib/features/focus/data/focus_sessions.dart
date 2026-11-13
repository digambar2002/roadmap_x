import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/local_changes.dart';
import '../../../core/services/synced_settings.dart';

/// One finished focus session.
class FocusSession {
  const FocusSession(
      {required this.start, required this.minutes, this.taskUid});

  final DateTime start;
  final int minutes;
  final String? taskUid;

  Map<String, dynamic> toJson() => {
        'start': start.toIso8601String(),
        'minutes': minutes,
        if (taskUid != null) 'task': taskUid,
      };

  static FocusSession? fromJson(Object? j) {
    if (j is! Map) return null;
    final start = DateTime.tryParse('${j['start']}');
    final minutes = (j['minutes'] as num?)?.toInt();
    if (start == null || minutes == null || minutes <= 0) return null;
    return FocusSession(
        start: start, minutes: minutes, taskUid: j['task'] as String?);
  }
}

/// A session that is counting down right now. Persisted so a session keeps
/// running — and still counts — if the app is closed in the middle of it.
class RunningFocus {
  const RunningFocus({
    required this.start,
    required this.endAt,
    required this.minutes,
    this.taskUid,
    this.taskText,
  });

  final DateTime start;
  final DateTime endAt;
  final int minutes;
  final String? taskUid;
  final String? taskText;

  Map<String, dynamic> toJson() => {
        'start': start.toIso8601String(),
        'endAt': endAt.toIso8601String(),
        'minutes': minutes,
        'task': taskUid,
        'taskText': taskText,
      };

  static RunningFocus? fromJson(Object? j) {
    if (j is! Map) return null;
    final start = DateTime.tryParse('${j['start']}');
    final endAt = DateTime.tryParse('${j['endAt']}');
    final minutes = (j['minutes'] as num?)?.toInt();
    if (start == null || endAt == null || minutes == null) return null;
    return RunningFocus(
      start: start,
      endAt: endAt,
      minutes: minutes,
      taskUid: j['task'] as String?,
      taskText: j['taskText'] as String?,
    );
  }
}

/// Focus history and the running session.
///
/// History is one synced setting, so focus time (and the XP it earns)
/// follows the account. Sessions shorter than [minimumMinutes] when given
/// up are not counted.
class FocusSessions {
  FocusSessions._();
  static final FocusSessions instance = FocusSessions._();

  static const historyKey = 'focus_sessions_v1';
  static const runningKey = 'focus_running';
  static const minimumMinutes = 5;

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<List<FocusSession>> history() async {
    final raw = (await _prefs).getString(historyKey);
    if (raw == null) return const [];
    try {
      return [
        for (final j in jsonDecode(raw) as List)
          if (FocusSession.fromJson(j) case final s?) s,
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<int> totalMinutes() async =>
      (await history()).fold<int>(0, (sum, s) => sum + s.minutes);

  Future<int> minutesOn(DateTime day) async => (await history())
      .where((s) =>
          s.start.year == day.year &&
          s.start.month == day.month &&
          s.start.day == day.day)
      .fold<int>(0, (sum, s) => sum + s.minutes);

  Future<void> add(FocusSession session) async {
    final prefs = await _prefs;
    final cutoff = DateTime.now().subtract(const Duration(days: 400));
    final next = [
      ...(await history()).where((s) => s.start.isAfter(cutoff)),
      session,
    ];
    await prefs.setString(
        historyKey, jsonEncode([for (final s in next) s.toJson()]));
    await SyncedSettings.instance.capture(prefs, historyKey);
    await LocalChanges.instance.notify();
  }

  Future<RunningFocus?> running() async {
    final raw = (await _prefs).getString(runningKey);
    if (raw == null) return null;
    try {
      return RunningFocus.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> setRunning(RunningFocus? r) async {
    final prefs = await _prefs;
    if (r == null) {
      await prefs.remove(runningKey);
    } else {
      await prefs.setString(runningKey, jsonEncode(r.toJson()));
    }
  }

  /// If a session ran out while the app was closed, record it. Returns the
  /// session credited, if any.
  Future<FocusSession?> settleRunning({DateTime? now}) async {
    final r = await running();
    if (r == null) return null;
    if ((now ?? DateTime.now()).isBefore(r.endAt)) return null;
    final session =
        FocusSession(start: r.start, minutes: r.minutes, taskUid: r.taskUid);
    await setRunning(null);
    await add(session);
    return session;
  }
}
