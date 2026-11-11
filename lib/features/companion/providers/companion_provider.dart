import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/gamification/gamification_service.dart';
import '../../../core/gamification/progress_engine.dart';
import '../../../core/services/habit_customization_service.dart';
import '../../analytics/providers/activity_provider.dart';
import '../../habits/providers/habit_provider.dart';
import '../../tasks/providers/task_provider.dart';

/// Bumped when the companion is renamed or switched between plant and pet.
final companionVersionProvider = StateProvider<int>((_) => 0);

/// Today's game state: the ring, the companion and the level.
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

  /// Nothing done yet today: the companion will lose health tonight.
  bool get isHungry => doneToday == 0;

  int get health => snapshot.health;
  LevelInfo get level => snapshot.level;

  CompanionMood get mood => moodFor(
        snapshot.health,
        doneToday: doneToday > 0,
        perfectToday: isPerfectToday,
      );

  /// What was earned today and fed to the companion: 💧 per habit, 🍎 per
  /// task, ⭐ for a perfect day.
  int get water => today.habitsDone;
  int get food => today.tasksDone;
  int get treats => isPerfectToday ? 1 : 0;
}

final gameStateProvider = FutureProvider<GameState>((ref) async {
  ref.watch(habitActivityTickProvider);
  ref.watch(activityTickProvider);
  ref.watch(taskChangesProvider);
  ref.watch(goalChangesProvider);
  ref.watch(habitsProvider);
  ref.watch(habitCustomizationVersionProvider);
  ref.watch(companionVersionProvider);
  final grouped = await ref.watch(todayTasksGroupedProvider.future);
  final snapshot = await GamificationService.instance.load();
  return GameState(
    snapshot: snapshot,
    openTasksToday: grouped.overdue.length + grouped.dueToday.length,
  );
});
