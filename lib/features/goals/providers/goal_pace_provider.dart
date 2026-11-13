import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/services/shared_preferences_provider.dart';
import '../../milestones/data/milestone_repository.dart';
import '../../tasks/data/task_repository.dart';
import '../../tasks/providers/task_provider.dart';
import '../data/goal_repository.dart';
import '../domain/goal_pace.dart';

Future<GoalPace> _paceFor(Goal goal) async {
  var total = 0;
  var done = 0;
  DateTime? last;
  for (final m in await MilestoneRepository.instance.getForGoal(goal.id)) {
    for (final t in await TaskRepository.instance.getForMilestone(m.id)) {
      if (t.deletedAt != null) continue;
      total++;
      if (t.isCompleted) {
        done++;
        final at = t.completedAt;
        if (at != null && (last == null || at.isAfter(last))) last = at;
      }
    }
  }
  return GoalPace.compute(
    createdAt: goal.createdAt,
    targetDate: goal.targetDate,
    totalTasks: total,
    doneTasks: done,
    lastActivity: last,
  );
}

/// Pace for one goal, kept fresh as its tasks change.
final goalPaceProvider =
    FutureProvider.family<GoalPace?, int>((ref, goalId) async {
  ref.watch(taskChangesProvider);
  ref.watch(goalChangesProvider);
  final goal = await GoalRepository.instance.getById(goalId);
  if (goal == null) return null;
  return _paceFor(goal);
});

/// How long a goal can sit untouched before Today nudges about it.
const staleAfterDays = 7;

/// How long "Later" hides a nudge.
const staleSnoozeDays = 3;

String staleSnoozeKey(String goalUid) => 'stale_snooze_$goalUid';

/// The active goal that has gone longest without progress, if any has gone
/// a week or more and its nudge isn't snoozed.
final staleGoalProvider =
    FutureProvider<({Goal goal, GoalPace pace})?>((ref) async {
  ref.watch(taskChangesProvider);
  ref.watch(goalChangesProvider);
  final prefs = ref.watch(sharedPreferencesProvider);
  final now = DateTime.now();
  ({Goal goal, GoalPace pace})? worst;
  for (final g in await GoalRepository.instance.getAll()) {
    if (g.isArchived) continue;
    final snoozedUntil =
        DateTime.tryParse(prefs.getString(staleSnoozeKey(g.uid)) ?? '');
    if (snoozedUntil != null && now.isBefore(snoozedUntil)) continue;
    final pace = await _paceFor(g);
    if (pace.status == PaceStatus.done || pace.status == PaceStatus.noTasks)
      continue;
    if (pace.staleDays < staleAfterDays) continue;
    if (worst == null || pace.staleDays > worst.pace.staleDays) {
      worst = (goal: g, pace: pace);
    }
  }
  return worst;
});
