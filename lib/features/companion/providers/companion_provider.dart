import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/gamification/gamification_service.dart';
import '../../../core/gamification/progress_engine.dart';
import '../../../core/services/habit_customization_service.dart';
import '../../analytics/providers/activity_provider.dart';
import '../../habits/providers/habit_provider.dart';
import '../../tasks/providers/task_provider.dart';

/// Today's game state: the perfect-day ring and the level.
class GameState {
  const GameState({required this.snapshot, required this.openTasksToday});

  final GameSnapshot snapshot;

  /// Overdue and due-today tasks not yet done.
  final int openTasksToday;

  DayActivity get today => snapshot.today;
  int get openHabitsToday =>
      (today.habitsDue - today.habitsDone).clamp(0, 1 << 30);
  int get doneToday => today.done;
  int get totalToday => doneToday + openHabitsToday + openTasksToday;

  /// How full the perfect-day ring is.
  double get ringProgress =>
      totalToday == 0 ? 0 : (doneToday / totalToday).clamp(0.0, 1.0);

  bool get isPerfectToday =>
      doneToday > 0 && openHabitsToday == 0 && openTasksToday == 0;

  bool get nothingDoneYet => doneToday == 0;

  LevelInfo get level => snapshot.level;

  /// XP earned so far today, and the coins it is worth.
  int get xpToday =>
      today.habitsDone * XpRules.habit +
      today.tasksDone * XpRules.task +
      (isPerfectToday ? XpRules.perfectDay : 0) +
      snapshot.focusMinutesToday * XpRules.focusMinute;
}

final gameStateProvider = FutureProvider<GameState>((ref) async {
  ref.watch(habitActivityTickProvider);
  ref.watch(activityTickProvider);
  ref.watch(taskChangesProvider);
  ref.watch(goalChangesProvider);
  ref.watch(habitsProvider);
  ref.watch(habitCustomizationVersionProvider);
  final grouped = await ref.watch(todayTasksGroupedProvider.future);
  final snapshot = await GamificationService.instance.load();
  return GameState(
    snapshot: snapshot,
    openTasksToday: grouped.overdue.length + grouped.dueToday.length,
  );
});
