import 'dart:math' as math;

enum PaceStatus { noTasks, done, ahead, onTrack, behind, overdue }

/// Is a goal on course to finish by its target date?
///
/// Compares the share of time used with the share of tasks done, and says
/// how many tasks a week are needed from here. Most to-do apps can't do
/// this because they have no deadlines or milestones; it is what makes this
/// a goal app.
class GoalPace {
  const GoalPace({
    required this.status,
    required this.timeUsed,
    required this.progress,
    required this.remaining,
    required this.daysLeft,
    required this.tasksPerWeek,
    required this.staleDays,
  });

  final PaceStatus status;

  /// 0–1: how much of the time between start and target has passed.
  final double timeUsed;

  /// 0–1: tasks done.
  final double progress;
  final int remaining;
  final int daysLeft;

  /// Tasks a week needed to finish on time (0 when done or overdue).
  final int tasksPerWeek;

  /// Days since anything in the goal was last completed (or since it was
  /// created, if nothing has been).
  final int staleDays;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static GoalPace compute({
    required DateTime createdAt,
    required DateTime targetDate,
    required int totalTasks,
    required int doneTasks,
    DateTime? lastActivity,
    DateTime? now,
  }) {
    final today = _day(now ?? DateTime.now());
    final start = _day(createdAt);
    final target = _day(targetDate);
    final span = math.max(1, target.difference(start).inDays);
    final elapsed = today.difference(start).inDays.clamp(0, span);
    final daysLeft = target.difference(today).inDays;
    final remaining = math.max(0, totalTasks - doneTasks);
    final timeUsed = elapsed / span;
    final progress = totalTasks == 0 ? 0.0 : doneTasks / totalTasks;
    final staleDays =
        math.max(0, today.difference(_day(lastActivity ?? createdAt)).inDays);

    PaceStatus status;
    if (totalTasks == 0) {
      status = PaceStatus.noTasks;
    } else if (remaining == 0) {
      status = PaceStatus.done;
    } else if (daysLeft < 0) {
      status = PaceStatus.overdue;
    } else if (progress - timeUsed >= 0.1) {
      status = PaceStatus.ahead;
    } else if (progress - timeUsed >= -0.1) {
      status = PaceStatus.onTrack;
    } else {
      status = PaceStatus.behind;
    }

    final weeksLeft = math.max(1.0, (daysLeft + 1) / 7);
    final perWeek = (status == PaceStatus.done || status == PaceStatus.overdue)
        ? 0
        : (remaining / weeksLeft).ceil();

    return GoalPace(
      status: status,
      timeUsed: timeUsed,
      progress: progress,
      remaining: remaining,
      daysLeft: daysLeft,
      tasksPerWeek: perWeek,
      staleDays: staleDays,
    );
  }

  /// One line for a goal card: where it stands and what it needs.
  String get summary => switch (status) {
        PaceStatus.noTasks => 'Add tasks to see your pace',
        PaceStatus.done => 'All tasks done 🎉',
        PaceStatus.overdue =>
          'Past the target date · $remaining task${remaining == 1 ? '' : 's'} left',
        PaceStatus.ahead => 'Ahead of schedule · $tasksPerWeek/week keeps it',
        PaceStatus.onTrack =>
          'On track · $tasksPerWeek task${tasksPerWeek == 1 ? '' : 's'}/week',
        PaceStatus.behind =>
          'Behind · $tasksPerWeek tasks/week to finish on time',
      };
}
