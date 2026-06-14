import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/models/models.dart';
import '../../../core/services/schedule_completion_service.dart';
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

final selectedScheduleDateProvider = StateProvider<DateTime>((_) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

final scheduleCompletedUidsProvider =
    FutureProvider.family<Set<String>, DateTime>((ref, date) {
  return ScheduleCompletionService.instance.getCompletedForDate(date);
});
