import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/models/models.dart';
import '../../../core/models/today_task.dart';
import '../../analytics/providers/activity_provider.dart';
import '../data/task_repository.dart';

class TodayTasksData {
  final List<TodayTaskContext> overdue;
  final List<TodayTaskContext> dueToday;
  final List<TodayTaskContext> thisWeek;
  final List<TodayTaskContext> noDueDate;

  const TodayTasksData({
    required this.overdue,
    required this.dueToday,
    required this.thisWeek,
    required this.noDueDate,
  });

  int get totalCount =>
      overdue.length + dueToday.length + thisWeek.length + noDueDate.length;

  int get actionableCount => overdue.length + dueToday.length + thisWeek.length;

  List<TodayTaskContext> get allOrdered => [
        ...overdue,
        ...dueToday,
        ...thisWeek,
        ...noDueDate,
      ];
}

final taskRepositoryProvider = Provider<TaskRepository>(
  (_) => TaskRepository.instance,
);

final tasksForMilestoneProvider =
    StreamProvider.family<List<Task>, int>((ref, milestoneId) {
  return ref.watch(taskRepositoryProvider).watchForMilestone(milestoneId);
});

final activeTaskContextsProvider = FutureProvider<List<TodayTaskContext>>((ref) {
  ref.watch(activityTickProvider);
  return ref.watch(taskRepositoryProvider).getActiveTaskContexts();
});

final todayTasksGroupedProvider = FutureProvider<TodayTasksData>((ref) async {
  ref.watch(activityTickProvider);
  await ref.watch(taskRepositoryProvider).watchAllTasks().first;
  final contexts =
      await ref.read(taskRepositoryProvider).getActiveTaskContexts();

  final overdue = <TodayTaskContext>[];
  final dueToday = <TodayTaskContext>[];
  final thisWeek = <TodayTaskContext>[];
  final noDueDate = <TodayTaskContext>[];

  for (final ctx in contexts) {
    if (ctx.isOverdue) {
      overdue.add(ctx);
    } else if (ctx.isDueToday) {
      dueToday.add(ctx);
    } else if (ctx.isDueThisWeek) {
      thisWeek.add(ctx);
    } else if (ctx.task.dueDate == null) {
      noDueDate.add(ctx);
    }
  }

  return TodayTasksData(
    overdue: overdue,
    dueToday: dueToday,
    thisWeek: thisWeek,
    noDueDate: noDueDate,
  );
});

/// Flat list of actionable tasks (overdue + today + this week).
final todayTasksProvider = FutureProvider<List<TodayTaskContext>>((ref) async {
  final grouped = await ref.watch(todayTasksGroupedProvider.future);
  return [
    ...grouped.overdue,
    ...grouped.dueToday,
    ...grouped.thisWeek,
  ];
});

final focusTasksProvider =
    FutureProvider.family<List<TodayTaskContext>, int>((ref, goalId) {
  ref.watch(activityTickProvider);
  return ref.watch(taskRepositoryProvider).getFocusTasks(goalId);
});
