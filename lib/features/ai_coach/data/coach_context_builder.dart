import 'package:isar_community/isar.dart';

import '../../../core/db/isar_service.dart';
import '../../../core/models/models.dart';

class CoachContextBuilder {
  Future<String> buildGlobalContext() async {
    final db = IsarService.instance.db;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));

    final goals = await db.goals.filter().isArchivedEqualTo(false).findAll();
    final tasks = await db.tasks.where().findAll();
    final completedTasks = tasks.where((t) => t.isCompleted).toList();

    final doneToday = completedTasks.where((t) {
      final d = t.completedAt;
      return d != null &&
          d.year == today.year &&
          d.month == today.month &&
          d.day == today.day;
    }).length;

    final doneThisWeek = completedTasks.where((t) {
      final d = t.completedAt;
      if (d == null) return false;
      final day = DateTime(d.year, d.month, d.day);
      return !day.isBefore(weekStart);
    }).length;

    final topGoals = await _topGoalsByOpenTasks(goals);

    return '''
Date: ${today.toIso8601String()}
Active goals: ${goals.length}
Total tasks: ${tasks.length}
Completed tasks: ${completedTasks.length}
Completed today: $doneToday
Completed this week: $doneThisWeek
Top goals to focus:
${topGoals.isEmpty ? '- None' : topGoals.join('\n')}
''';
  }

  Future<String> buildGoalContext(int goalId) async {
    final db = IsarService.instance.db;
    final goal = await db.goals.get(goalId);
    if (goal == null) {
      return 'Goal $goalId not found.';
    }

    await goal.milestones.load();
    final milestones = goal.milestones.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final rows = <String>[];
    int total = 0;
    int done = 0;

    for (final m in milestones) {
      await m.tasks.load();
      final tasks = m.tasks.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      final completed = tasks.where((t) => t.isCompleted).length;
      total += tasks.length;
      done += completed;
      rows.add('- ${m.title}: $completed/${tasks.length} tasks done');
      for (final t in tasks.take(6)) {
        final mark = t.isCompleted ? 'x' : ' ';
        rows.add('  [$mark] ${t.text}');
      }
    }

    return '''
Goal: ${goal.emoji} ${goal.name}
Description: ${goal.description}
Target date: ${goal.targetDate.toIso8601String()}
Progress: $done/$total tasks done
Milestone breakdown:
${rows.isEmpty ? '- No milestones yet' : rows.join('\n')}
''';
  }

  Future<List<String>> _topGoalsByOpenTasks(List<Goal> goals) async {
    final scored = <({Goal goal, int open})>[];
    for (final goal in goals) {
      await goal.milestones.load();
      int open = 0;
      for (final m in goal.milestones) {
        await m.tasks.load();
        open += m.tasks.where((t) => !t.isCompleted).length;
      }
      scored.add((goal: goal, open: open));
    }
    scored.sort((a, b) => b.open.compareTo(a.open));
    return scored
        .where((s) => s.open > 0)
        .take(3)
        .map((s) => '- ${s.goal.emoji} ${s.goal.name}: ${s.open} open tasks')
        .toList();
  }
}
