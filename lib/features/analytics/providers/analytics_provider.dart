import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';
import '../../../core/db/isar_service.dart';
import '../../../core/models/models.dart';
import '../../../core/utils/progress_utils.dart';

class AnalyticsData {
  final int thisWeekDone;
  final int lastWeekDone;
  final List<int> last7Days; // tasks done per day (today=last)
  final int currentStreak;
  final int longestStreak;
  final String bestDay; // day name with most completions
  final List<GoalStat> goalStats;
  final Map<int, int> monthlyHeatmap; // day-of-month → count

  const AnalyticsData({
    required this.thisWeekDone,
    required this.lastWeekDone,
    required this.last7Days,
    required this.currentStreak,
    required this.longestStreak,
    required this.bestDay,
    required this.goalStats,
    required this.monthlyHeatmap,
  });

  double get weekChangePercent {
    if (lastWeekDone == 0) return 0;
    return (thisWeekDone - lastWeekDone) / lastWeekDone;
  }
}

class GoalStat {
  final Goal goal;
  final double percent;
  final int done;
  final int total;
  const GoalStat({
    required this.goal,
    required this.percent,
    required this.done,
    required this.total,
  });
}

final analyticsDataProvider = FutureProvider<AnalyticsData>((ref) async {
  final db = IsarService.instance.db;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final allTasks = await db.tasks.where().anyId().build().findAll();
  final completedTasks = allTasks.where((t) => t.isCompleted).toList();

  // This week (Mon–Sun)
  final weekStart = today.subtract(Duration(days: today.weekday - 1));
  final lastWeekStart = weekStart.subtract(const Duration(days: 7));

  int thisWeek = 0, lastWeek = 0;
  final last7 = List.filled(7, 0);
  final Map<int, int> heatmap = {};

  for (final t in completedTasks) {
    if (t.completedAt == null) continue;
    final d =
        DateTime(t.completedAt!.year, t.completedAt!.month, t.completedAt!.day);

    if (!d.isBefore(weekStart)) thisWeek++;
    if (!d.isBefore(lastWeekStart) && d.isBefore(weekStart)) lastWeek++;

    // Last 7 days bar chart
    final daysAgo = today.difference(d).inDays;
    if (daysAgo >= 0 && daysAgo < 7) {
      last7[6 - daysAgo]++;
    }

    // Monthly heatmap
    if (d.month == now.month && d.year == now.year) {
      heatmap[d.day] = (heatmap[d.day] ?? 0) + 1;
    }
  }

  // Best day
  final dayTotals = <int, int>{};
  for (final t in completedTasks) {
    if (t.completedAt == null) continue;
    final wd = t.completedAt!.weekday % 7;
    dayTotals[wd] = (dayTotals[wd] ?? 0) + 1;
  }
  const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  String bestDay = '--';
  if (dayTotals.isNotEmpty) {
    final best = dayTotals.entries.reduce((a, b) => a.value > b.value ? a : b);
    bestDay = dayNames[best.key];
  }

  // Streak
  final completedDates = completedTasks
      .where((t) => t.completedAt != null)
      .map((t) => t.completedAt!)
      .toList();
  final streak = ProgressUtils.calculateStreak(completedDates);

  // Longest streak
  final days = completedDates
      .map((d) => DateTime(d.year, d.month, d.day))
      .toSet()
      .toList()
    ..sort();
  int longest = 0, cur = 0;
  DateTime? prev;
  for (final d in days) {
    if (prev != null && d.difference(prev).inDays == 1) {
      cur++;
    } else {
      cur = 1;
    }
    if (cur > longest) longest = cur;
    prev = d;
  }

  // Per-goal stats
  final goals = await db.goals.filter().isArchivedEqualTo(false).findAll();
  final goalStats = <GoalStat>[];
  for (final g in goals) {
    await g.milestones.load();
    int gt = 0, gd = 0;
    for (final ms in g.milestones) {
      await ms.tasks.load();
      gt += ms.tasks.length as int;
      gd += ms.tasks.where((t) => t.isCompleted).length as int;
    }
    goalStats.add(GoalStat(
      goal: g,
      percent: ProgressUtils.goalProgress(totalTasks: gt, completedTasks: gd),
      done: gd,
      total: gt,
    ));
  }
  goalStats.sort((a, b) => b.percent.compareTo(a.percent));

  return AnalyticsData(
    thisWeekDone: thisWeek,
    lastWeekDone: lastWeek,
    last7Days: last7,
    currentStreak: streak,
    longestStreak: longest,
    bestDay: bestDay,
    goalStats: goalStats,
    monthlyHeatmap: heatmap,
  );
});
