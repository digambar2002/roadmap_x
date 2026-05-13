import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/models/models.dart';
import '../data/schedule_repository.dart';

final scheduleRepositoryProvider = Provider<ScheduleRepository>(
  (_) => ScheduleRepository.instance,
);

final allScheduleItemsProvider = StreamProvider<List<ScheduleItem>>((ref) {
  return ref.watch(scheduleRepositoryProvider).watchAll();
});

final scheduleForWeekdayProvider =
    StreamProvider.family<List<ScheduleItem>, int>((ref, weekday) {
  return ref.watch(scheduleRepositoryProvider).watchForWeekday(weekday);
});

// Currently selected weekday for the schedule screen
final selectedWeekdayProvider = StateProvider<int>((ref) {
  return DateTime.now().weekday % 7; // 0=Sun..6=Sat
});
