class ProgressUtils {
  ProgressUtils._();

  static double goalProgress({
    required int totalTasks,
    required int completedTasks,
  }) {
    if (totalTasks == 0) return 0.0;
    return (completedTasks / totalTasks).clamp(0.0, 1.0);
  }

  static String progressLabel(double progress) =>
      '${(progress * 100).toStringAsFixed(0)}%';

  /// Calculate streak: consecutive days (ending today or yesterday)
  /// where at least one task was completed.
  static int calculateStreak(List<DateTime> completedDates) {
    if (completedDates.isEmpty) return 0;

    final days = completedDates
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    final today = DateTime.now();
    final todayNorm = DateTime(today.year, today.month, today.day);
    // Date-component arithmetic: Duration subtraction across a DST change
    // lands at 23:00 two days back and never equals a normalized date.
    final yesterday = DateTime(today.year, today.month, today.day - 1);

    // Streak must start from today or yesterday
    if (days.first != todayNorm && days.first != yesterday) return 0;

    int streak = 1;
    for (int i = 0; i < days.length - 1; i++) {
      if (_dayDiff(days[i], days[i + 1]) == 1) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  /// Exact calendar-day difference, immune to DST (local midnights can be
  /// 23/25h apart, which truncates to 0 with a plain inDays).
  static int _dayDiff(DateTime a, DateTime b) => DateTime.utc(
        a.year,
        a.month,
        a.day,
      ).difference(DateTime.utc(b.year, b.month, b.day)).inDays;
}
