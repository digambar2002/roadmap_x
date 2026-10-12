import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/services/habit_checkin_service.dart';
import '../../../core/sync/sync_service.dart';
import '../../analytics/providers/activity_provider.dart';
import '../data/habit_repository.dart';

final habitRepositoryProvider = Provider<HabitRepository>(
  (_) => HabitRepository.instance,
);

final habitCheckinServiceProvider = Provider<HabitCheckinService>(
  (_) => HabitCheckinService.instance,
);

/// The user's habits, in their chosen order.
final habitsProvider = StreamProvider<List<Habit>>((ref) {
  return ref.watch(habitRepositoryProvider).watchAll();
});

/// Which habits are ticked today, by habit uid.
class TodayHabitChecksNotifier extends AsyncNotifier<Set<String>> {
  DateTime? _builtForDay;

  @override
  Future<Set<String>> build() async {
    // A merge from another device writes check-ins straight into the database,
    // bypassing the tick bumped by [toggle].
    final sub = SyncService.instance.merged.listen((_) {
      ref.read(habitActivityTickProvider.notifier).state++;
      ref.invalidateSelf();
    });
    ref.onDispose(sub.cancel);

    final now = DateTime.now();
    _builtForDay = DateTime(now.year, now.month, now.day);
    return ref.read(habitCheckinServiceProvider).getCheckedForDate(now);
  }

  Future<void> toggle(String habitUid) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final service = ref.read(habitCheckinServiceProvider);

    // If the app stayed open past midnight, the built state belongs to
    // yesterday — toggling from it would seed today with stale values.
    // Re-read today's stored checks instead of trusting cached state.
    final stale = _builtForDay != today;
    final current = stale
        ? await service.getCheckedForDate(now)
        : (state.valueOrNull ?? await service.getCheckedForDate(now));
    _builtForDay = today;

    final willCheck = !current.contains(habitUid);
    await service.setChecked(now, habitUid, willCheck);

    final updated = Set<String>.from(current);
    if (willCheck) {
      updated.add(habitUid);
    } else {
      updated.remove(habitUid);
    }
    state = AsyncData(updated);
    ref.read(habitActivityTickProvider.notifier).state++;
    ref.read(activityTickProvider.notifier).state++;
  }
}

final todayHabitChecksProvider =
    AsyncNotifierProvider<TodayHabitChecksNotifier, Set<String>>(
  TodayHabitChecksNotifier.new,
);

final habitChecksForDateProvider =
    FutureProvider.family<Set<String>, DateTime>((ref, date) async {
  ref.watch(habitActivityTickProvider);
  return ref.read(habitCheckinServiceProvider).getCheckedForDate(date);
});

final habitWeeklyProgressProvider =
    FutureProvider<Map<String, int>>((ref) async {
  ref.watch(habitActivityTickProvider);
  final service = ref.read(habitCheckinServiceProvider);
  final now = DateTime.now();
  final counts = <String, int>{};

  for (var i = 0; i < 7; i++) {
    final d = now.subtract(Duration(days: i));
    final checked = await service.getCheckedForDate(d);
    for (final uid in checked) {
      counts[uid] = (counts[uid] ?? 0) + 1;
    }
  }
  return counts;
});

final habitCompletedDaysInWeekProvider =
    FutureProvider.family<Set<String>, DateTime>((ref, weekStart) async {
  ref.watch(habitActivityTickProvider);
  final service = ref.read(habitCheckinServiceProvider);
  final completed = <String>{};

  for (var i = 0; i < 7; i++) {
    final d = weekStart.add(Duration(days: i));
    if (await service.isDayComplete(d)) {
      final key =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      completed.add(key);
    }
  }
  return completed;
});

final habitStreakProvider = FutureProvider<int>((ref) async {
  ref.watch(habitActivityTickProvider);
  return ref.read(habitCheckinServiceProvider).getCurrentStreak();
});

final habitActivityTickProvider = StateProvider<int>((_) => 0);
