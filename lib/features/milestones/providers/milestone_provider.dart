import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/models/models.dart';
import '../data/milestone_repository.dart';

final milestoneRepositoryProvider = Provider<MilestoneRepository>(
  (_) => MilestoneRepository.instance,
);

final milestonesForGoalProvider =
    StreamProvider.family<List<Milestone>, int>((ref, goalId) {
  return ref.watch(milestoneRepositoryProvider).watchForGoal(goalId);
});
