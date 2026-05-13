import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/models/models.dart';
import '../../../core/utils/progress_utils.dart';
import '../../goals/providers/goal_provider.dart';
import '../../milestones/providers/milestone_provider.dart';
import '../../tasks/providers/task_provider.dart';

class DashboardData {
  final double overallPercent;
  final int totalDone;
  final int totalTasks;
  final List<Goal> goals;
  final Map<int, double> goalProgress; // goalId → percent
  final Map<int, String> goalProgressLabel;

  const DashboardData({
    required this.overallPercent,
    required this.totalDone,
    required this.totalTasks,
    required this.goals,
    required this.goalProgress,
    required this.goalProgressLabel,
  });
}

final dashboardDataProvider = Provider<AsyncValue<DashboardData>>((ref) {
  final goalsAsync = ref.watch(activeGoalsProvider);

  return goalsAsync.when(
    loading: () => const AsyncLoading(),
    error: (error, stackTrace) => AsyncError(error, stackTrace),
    data: (goals) {
      int total = 0;
      int done = 0;
      final progress = <int, double>{};
      final progressLabel = <int, String>{};

      for (final goal in goals) {
        final milestonesAsync = ref.watch(milestonesForGoalProvider(goal.id));
        final milestones = milestonesAsync.valueOrNull ?? const <Milestone>[];

        int goalTotal = 0;
        int goalDone = 0;

        for (final milestone in milestones) {
          final tasksAsync = ref.watch(tasksForMilestoneProvider(milestone.id));
          final tasks = tasksAsync.valueOrNull ?? const <Task>[];
          goalTotal += tasks.length;
          goalDone += tasks.where((task) => task.isCompleted).length;
        }

        total += goalTotal;
        done += goalDone;

        final percent = ProgressUtils.goalProgress(
          totalTasks: goalTotal,
          completedTasks: goalDone,
        );
        progress[goal.id] = percent;
        progressLabel[goal.id] = ProgressUtils.progressLabel(percent);
      }

      return AsyncData(
        DashboardData(
          overallPercent: ProgressUtils.goalProgress(
            totalTasks: total,
            completedTasks: done,
          ),
          totalDone: done,
          totalTasks: total,
          goals: goals,
          goalProgress: progress,
          goalProgressLabel: progressLabel,
        ),
      );
    },
  );
});
