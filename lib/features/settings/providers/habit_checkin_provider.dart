import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../analytics/providers/activity_provider.dart';
import '../../../core/services/habit_checkin_service.dart';
import '../../../core/sync/sync_service.dart';

final habitCheckinServiceProvider = Provider<HabitCheckinService>(
  (_) => HabitCheckinService.instance,
);

class TodayHabitChecksNotifier extends AsyncNotifier<List<bool>> {
  DateTime? _builtForDay;

  @override
  Future<List<bool>> build() async {
    // A merge from another device writes check-ins straight into the database,
    // bypassing the tick bumped by [toggle].
    final sub = SyncService.instance.merged.listen((_) {
      ref.read(habitActivityTickProvider.notifier).state++;
      ref.invalidateSelf();
    });
    ref.onDispose(sub.cancel);

    final now = DateTime.now();
    _builtForDay = DateTime(now.year, now.month, now.day);
    return ref.read(habitCheckinServiceProvider).getChecksForDate(now);
  }

  Future<void> toggle(int index) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final service = ref.read(habitCheckinServiceProvider);

    // If the app stayed open past midnight, the built state belongs to
    // yesterday — toggling from it would seed today with stale values.
    // Re-read today's stored checks instead of trusting cached state.
    final stale = _builtForDay != today;
    final current = stale
        ? await service.getChecksForDate(now)
        : (state.valueOrNull ?? await service.getChecksForDate(now));
    _builtForDay = today;

    final nextValue = !current[index];
    await service.setCheckForDate(now, index, nextValue);
    final updated = List<bool>.from(current)..[index] = nextValue;
    state = AsyncData(updated);
    ref.read(habitActivityTickProvider.notifier).state++;
    ref.read(activityTickProvider.notifier).state++;
  }
}

final todayHabitChecksProvider =
    AsyncNotifierProvider<TodayHabitChecksNotifier, List<bool>>(
  TodayHabitChecksNotifier.new,
);

final habitStreakProvider = FutureProvider<int>((ref) async {
  final _ = ref.watch(habitActivityTickProvider);
  return ref.read(habitCheckinServiceProvider).getCurrentStreak();
});

final habitActivityTickProvider = StateProvider<int>((_) => 0);
