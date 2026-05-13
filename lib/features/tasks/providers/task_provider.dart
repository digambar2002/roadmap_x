import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/models/models.dart';
import '../data/task_repository.dart';

final taskRepositoryProvider = Provider<TaskRepository>(
  (_) => TaskRepository.instance,
);

final tasksForMilestoneProvider =
    StreamProvider.family<List<Task>, int>((ref, milestoneId) {
  return ref.watch(taskRepositoryProvider).watchForMilestone(milestoneId);
});
