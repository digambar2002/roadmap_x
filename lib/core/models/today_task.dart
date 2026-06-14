import 'models.dart';

class TodayTaskContext {
  final Task task;
  final Goal? goal;
  final Milestone? milestone;

  const TodayTaskContext({
    required this.task,
    this.goal,
    this.milestone,
  });

  DateTime? get dueDate => task.dueDate;

  bool get isOverdue {
    final due = dueDate;
    if (due == null || task.isCompleted) return false;
    final now = DateTime.now();
    final dueDay = DateTime(due.year, due.month, due.day);
    final today = DateTime(now.year, now.month, now.day);
    return dueDay.isBefore(today);
  }

  bool get isDueToday {
    final due = dueDate;
    if (due == null) return false;
    final now = DateTime.now();
    return due.year == now.year && due.month == now.month && due.day == now.day;
  }

  bool get isDueThisWeek {
    final due = dueDate;
    if (due == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));
    final dueDay = DateTime(due.year, due.month, due.day);
    return !dueDay.isBefore(weekStart) && !dueDay.isAfter(weekEnd);
  }
}
