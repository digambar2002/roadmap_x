import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../analytics/providers/activity_provider.dart';
import '../../../core/services/habit_checkin_service.dart';

final habitCheckinServiceProvider = Provider<HabitCheckinService>(
  (_) => HabitCheckinService.instance,
);

class TodayHabitChecksNotifier extends AsyncNotifier<List<bool>> {
  @override
  Future<List<bool>> build() async {
    return ref
        .read(habitCheckinServiceProvider)
        .getChecksForDate(DateTime.now());
  }

  Future<void> toggle(int index) async {
    final current = state.valueOrNull ?? List<bool>.filled(4, false);
    final nextValue = !current[index];
    await ref
        .read(habitCheckinServiceProvider)
        .setCheckForDate(DateTime.now(), index, nextValue);
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
