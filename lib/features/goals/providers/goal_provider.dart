import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/models/models.dart';
import '../data/goal_repository.dart';

final goalRepositoryProvider = Provider<GoalRepository>(
  (_) => GoalRepository.instance,
);

// All goals stream
final allGoalsProvider = StreamProvider<List<Goal>>((ref) {
  return ref.watch(goalRepositoryProvider).watchAll();
});

// Active goals only
final activeGoalsProvider = StreamProvider<List<Goal>>((ref) {
  return ref.watch(goalRepositoryProvider).watchActive();
});

// Single goal
final goalByIdProvider = StreamProvider.family<Goal?, int>((ref, id) {
  return ref.watch(goalRepositoryProvider).watchById(id);
});

// Goals filter state: 'all' | 'active' | 'archived'
final goalFilterProvider = StateProvider<String>((_) => 'active');

// Filtered goals
final filteredGoalsProvider = Provider<AsyncValue<List<Goal>>>((ref) {
  final filter = ref.watch(goalFilterProvider);
  final allAsync = ref.watch(allGoalsProvider);

  return allAsync.whenData((goals) {
    switch (filter) {
      case 'archived':
        return goals.where((g) => g.isArchived).toList();
      case 'active':
        return goals.where((g) => !g.isArchived).toList();
      default:
        return goals;
    }
  });
});
