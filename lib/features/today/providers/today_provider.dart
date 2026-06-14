import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../tasks/providers/task_provider.dart';

class TodayData {
  final int total;
  final int overdue;
  final int dueToday;
  final int dueThisWeek;

  const TodayData({
    required this.total,
    required this.overdue,
    required this.dueToday,
    required this.dueThisWeek,
  });
}

final todayDataProvider = Provider<AsyncValue<TodayData>>((ref) {
  final tasksAsync = ref.watch(todayTasksGroupedProvider);
  return tasksAsync.whenData(
    (data) => TodayData(
      total: data.actionableCount,
      overdue: data.overdue.length,
      dueToday: data.dueToday.length,
      dueThisWeek: data.thisWeek.length,
    ),
  );
});
