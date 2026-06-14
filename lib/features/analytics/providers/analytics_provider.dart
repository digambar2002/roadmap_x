import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../../../core/db/isar_service.dart';
import '../../../core/models/models.dart';
import '../../../core/services/habit_checkin_service.dart';
import '../../../core/services/schedule_completion_service.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/progress_utils.dart';
import 'activity_provider.dart';

class AnalyticsData {
  final int thisWeekDone;
  final int lastWeekDone;
  final List<int> last7Days;
  final int currentStreak;
  final int longestStreak;
  final String bestDay;
  final List<GoalStat> goalStats;
  final Map<int, int> monthlyHeatmap;
  final WeeklyReview weeklyReview;

  const AnalyticsData({
    required this.thisWeekDone,
    required this.lastWeekDone,
    required this.last7Days,
    required this.currentStreak,
    required this.longestStreak,
    required this.bestDay,
    required this.goalStats,
    required this.monthlyHeatmap,
    required this.weeklyReview,
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

class WeeklyReview {
  final int completedGoals;
  final int needsAttention;
  final int overdueTasks;
  final String summary;

  const WeeklyReview({
    required this.completedGoals,
    required this.needsAttention,
    required this.overdueTasks,
    required this.summary,
  });
}

final analyticsDataProvider = FutureProvider<AnalyticsData>((ref) async {
  ref.watch(activityTickProvider);

  final db = IsarService.instance.db;
  final now = DateTime.now();
  final today = AppDateUtils.normalizeDate(now);

  final allTasks = await db.tasks.where().anyId().build().findAll();
  final completedTasks = allTasks.where((t) => t.isCompleted).toList();

  final habitCompleteDays =
      await HabitCheckinService.instance.getCompleteDates();
  final scheduleCompleteDays =
      await ScheduleCompletionService.instance.getCompletedDates();

  final activeDays = <DateTime>{};
  for (final t in completedTasks) {
    if (t.completedAt != null) {
      activeDays.add(AppDateUtils.normalizeDate(t.completedAt!));
    }
  }
  activeDays.addAll(habitCompleteDays);
  activeDays.addAll(scheduleCompleteDays);

  final activityCountByDay = <DateTime, int>{};
  void bumpDay(DateTime day, [int amount = 1]) {
    final d = AppDateUtils.normalizeDate(day);
    activityCountByDay[d] = (activityCountByDay[d] ?? 0) + amount;
  }

  for (final t in completedTasks) {
    if (t.completedAt != null) bumpDay(t.completedAt!);
  }
  for (final day in habitCompleteDays) {
    bumpDay(day);
  }
  for (final day in scheduleCompleteDays) {
    final count =
        await ScheduleCompletionService.instance.completedCountOnDate(day);
    activityCountByDay[day] = (activityCountByDay[day] ?? 0) + count;
  }

  final weekStart = today.subtract(Duration(days: today.weekday - 1));
  final lastWeekStart = weekStart.subtract(const Duration(days: 7));

  int thisWeek = 0, lastWeek = 0;
  final last7 = List.filled(7, 0);
  final heatmap = <int, int>{};

  for (final entry in activityCountByDay.entries) {
    final d = entry.key;
    final count = entry.value;

    if (!d.isBefore(weekStart)) thisWeek += count;
    if (!d.isBefore(lastWeekStart) && d.isBefore(weekStart)) lastWeek += count;

    final daysAgo = today.difference(d).inDays;
    if (daysAgo >= 0 && daysAgo < 7) {
      last7[6 - daysAgo] += count;
    }

    if (d.month == now.month && d.year == now.year) {
      heatmap[d.day] = (heatmap[d.day] ?? 0) + count;
    }
  }

  const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  final dayTotals = <int, int>{};
  for (final entry in activityCountByDay.entries) {
    final wd = entry.key.weekday % 7;
    dayTotals[wd] = (dayTotals[wd] ?? 0) + entry.value;
  }
  String bestDay = '--';
  if (dayTotals.isNotEmpty) {
    final best = dayTotals.entries.reduce((a, b) => a.value > b.value ? a : b);
    bestDay = dayNames[best.key];
  }

  final streak = ProgressUtils.calculateStreak(activeDays.toList());

  final sortedDays = activeDays.toList()..sort();
  int longest = 0, cur = 0;
  DateTime? prev;
  for (final d in sortedDays) {
    if (prev != null && d.difference(prev).inDays == 1) {
      cur++;
    } else {
      cur = 1;
    }
    if (cur > longest) longest = cur;
    prev = d;
  }

  final goals = await db.goals.filter().isArchivedEqualTo(false).findAll();
  final goalStats = <GoalStat>[];
  for (final g in goals) {
    await g.milestones.load();
    int gt = 0, gd = 0;
    for (final ms in g.milestones) {
      await ms.tasks.load();
      gt += ms.tasks.length;
      gd += ms.tasks.where((t) => t.isCompleted).length;
    }
    goalStats.add(GoalStat(
      goal: g,
      percent: ProgressUtils.goalProgress(totalTasks: gt, completedTasks: gd),
      done: gd,
      total: gt,
    ));
  }
  goalStats.sort((a, b) => b.percent.compareTo(a.percent));

  int completedGoals = 0;
  int needsAttention = 0;
  int overdueTasks = 0;

  for (final stat in goalStats) {
    if (stat.total > 0 && stat.percent >= 1.0) completedGoals++;
    if (stat.total > 0 && stat.percent < 0.25) needsAttention++;
  }

  for (final t in allTasks) {
    if (t.isCompleted || t.dueDate == null) continue;
    final d = AppDateUtils.normalizeDate(t.dueDate!);
    if (d.isBefore(today)) overdueTasks++;
  }

  String summary;
  if (thisWeek == 0 && overdueTasks > 0) {
    summary =
        'You have $overdueTasks overdue task${overdueTasks == 1 ? '' : 's'}. Focus on clearing those this week.';
  } else if (thisWeek > lastWeek) {
    summary =
        'Great momentum! $thisWeek activities logged this week, up from $lastWeek last week.';
  } else if (completedGoals > 0) {
    summary =
        '$completedGoals goal${completedGoals == 1 ? '' : 's'} fully complete. Consider archiving or setting new targets.';
  } else if (needsAttention > 0) {
    summary =
        '$needsAttention goal${needsAttention == 1 ? '' : 's'} below 25% progress. Break them into smaller tasks.';
  } else {
    summary = 'Keep showing up — consistency beats intensity.';
  }

  return AnalyticsData(
    thisWeekDone: thisWeek,
    lastWeekDone: lastWeek,
    last7Days: last7,
    currentStreak: streak,
    longestStreak: longest,
    bestDay: bestDay,
    goalStats: goalStats,
    monthlyHeatmap: heatmap,
    weeklyReview: WeeklyReview(
      completedGoals: completedGoals,
      needsAttention: needsAttention,
      overdueTasks: overdueTasks,
      summary: summary,
    ),
  );
});
