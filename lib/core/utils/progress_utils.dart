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
    final yesterday = todayNorm.subtract(const Duration(days: 1));

    // Streak must start from today or yesterday
    if (days.first != todayNorm && days.first != yesterday) return 0;

    int streak = 1;
    for (int i = 0; i < days.length - 1; i++) {
      final diff = days[i].difference(days[i + 1]).inDays;
      if (diff == 1) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }
}
