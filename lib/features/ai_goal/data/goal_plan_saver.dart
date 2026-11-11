import '../../../core/ai/gemini_service.dart';
import '../../goals/data/goal_repository.dart';
import '../../milestones/data/milestone_repository.dart';
import '../../tasks/data/task_repository.dart';

/// Writes a goal plan — from the AI or from pasted text — as a goal with its
/// milestones and tasks. All or nothing: if any write fails, the half-built
/// goal is removed so a retry can't leave a partial duplicate behind.
Future<int> saveGoalPlan(AiGoalResponse plan, {String? goalName}) async {
  final name = (goalName ?? plan.goal.name).trim();
  var goalId = 0;
  try {
    final goal = await GoalRepository.instance.create(
      name: name.isEmpty ? 'Untitled Goal' : name,
      description: plan.goal.description,
      emoji: plan.goal.emoji.isEmpty ? '🎯' : plan.goal.emoji,
      colorHex: parsePlanColor(plan.goal.colorHex),
      targetDate: targetDateFromDuration(plan.goal.durationLabel),
    );
    goalId = goal.id;

    final milestones = [...plan.milestones]
      ..sort((a, b) => a.order.compareTo(b.order));
    for (final m in milestones) {
      final saved = await MilestoneRepository.instance.create(
        goalId: goal.id,
        title: m.title.isEmpty ? 'Milestone' : m.title,
        theme: m.theme,
      );
      final tasks = [...m.tasks]..sort((a, b) => a.order.compareTo(b.order));
      for (final t in tasks) {
        await TaskRepository.instance.create(
          milestoneId: saved.id,
          text: t.text,
          priority: t.priority.clamp(0, 2),
          note: t.note.trim().isEmpty ? null : t.note.trim(),
        );
      }
    }
    return goal.id;
  } catch (_) {
    if (goalId != 0) {
      try {
        await GoalRepository.instance.delete(goalId);
      } catch (_) {}
    }
    rethrow;
  }
}

int parsePlanColor(String colorHex) {
  final normalized = colorHex.trim().replaceFirst('#', '').toUpperCase();
  if (normalized.length != 6) return 0xFF5B9CF6;
  return int.tryParse('FF$normalized', radix: 16) ?? 0xFF5B9CF6;
}

DateTime targetDateFromDuration(String label) {
  final now = DateTime.now();
  final lower = label.toLowerCase();
  final number = int.tryParse(RegExp(r'\d+').stringMatch(lower) ?? '');
  if (number == null) return now.add(const Duration(days: 90));
  if (lower.contains('week')) return now.add(Duration(days: number * 7));
  if (lower.contains('month')) return now.add(Duration(days: number * 30));
  if (lower.contains('year')) return now.add(Duration(days: number * 365));
  return now.add(const Duration(days: 90));
}
