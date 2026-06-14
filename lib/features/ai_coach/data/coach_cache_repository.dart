import 'dart:convert';

import '../../../core/ai/ai_coach_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CoachCacheRepository {
  static const _kDailyPrefix = 'ai_coach_daily_';
  static const _kWeeklyPrefix = 'ai_coach_weekly_';

  final SharedPreferences _prefs;
  CoachCacheRepository(this._prefs);

  Future<void> saveDaily(DailyBriefing briefing, DateTime day) async {
    final key = '$_kDailyPrefix${_dayKey(day)}';
    await _prefs.setString(key, jsonEncode(briefing.toJson()));
  }

  DailyBriefing? readDaily(DateTime day) {
    final key = '$_kDailyPrefix${_dayKey(day)}';
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return DailyBriefing(
      headline: (json['headline'] ?? '').toString(),
      focusTask: (json['focus_task'] ?? '').toString(),
      quickWin: (json['quick_win'] ?? '').toString(),
      risk: (json['risk'] ?? '').toString(),
      coachTip: (json['coach_tip'] ?? '').toString(),
      generatedAt: DateTime.tryParse((json['generated_at'] ?? '').toString()) ?? DateTime.now(),
    );
  }

  Future<void> saveWeekly(WeeklyCoachReview review, DateTime weekStart) async {
    final key = '$_kWeeklyPrefix${_dayKey(weekStart)}';
    await _prefs.setString(key, jsonEncode(review.toJson()));
  }

  WeeklyCoachReview? readWeekly(DateTime weekStart) {
    final key = '$_kWeeklyPrefix${_dayKey(weekStart)}';
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return WeeklyCoachReview(
      summary: (json['summary'] ?? '').toString(),
      wins: ((json['wins'] as List?) ?? const []).map((e) => e.toString()).toList(),
      blockers: ((json['blockers'] as List?) ?? const []).map((e) => e.toString()).toList(),
      nextWeekFocus: ((json['next_week_focus'] as List?) ?? const []).map((e) => e.toString()).toList(),
      consistencyScore: ((json['consistency_score'] as num?)?.toInt() ?? 0).clamp(0, 100),
      generatedAt: DateTime.tryParse((json['generated_at'] ?? '').toString()) ?? DateTime.now(),
    );
  }

  String _dayKey(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
