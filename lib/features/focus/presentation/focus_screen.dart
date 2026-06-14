import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/widgets/animated_checkbox.dart';
import '../../../shared/widgets/due_date_badge.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../analytics/providers/activity_provider.dart';
import '../../goals/providers/goal_provider.dart';
import '../../tasks/data/task_repository.dart';
import '../../tasks/providers/task_provider.dart';

class FocusScreen extends ConsumerWidget {
  final int goalId;
  const FocusScreen({super.key, required this.goalId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final goalAsync = ref.watch(goalByIdProvider(goalId));
    final tasksAsync = ref.watch(focusTasksProvider(goalId));

    return Scaffold(
      backgroundColor: cs.background,
      appBar: AppBar(
        title: const Text('Focus Mode'),
        backgroundColor: cs.background,
      ),
      body: goalAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (goal) {
          if (goal == null) {
            return const Center(child: Text('Goal not found'));
          }
          final goalColor = Color(goal.colorHex);

          return tasksAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (items) {
              if (items.isEmpty) {
                return EmptyState(
                  emoji: '🎯',
                  title: 'Nothing to focus on',
                  subtitle: 'All tasks for ${goal.name} are complete!',
                  buttonLabel: 'Back to goal',
                  onButton: () => context.pop(),
                );
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          goalColor.withOpacity(0.18),
                          goalColor.withOpacity(0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: goalColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Text(goal.emoji, style: const TextStyle(fontSize: 32)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                goal.name,
                                style: tt.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              Text(
                                'Top ${items.length} priority task${items.length == 1 ? '' : 's'}',
                                style: tt.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 250.ms),
                  const SizedBox(height: 16),
                  Text(
                    'Work through these one at a time',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  ...items.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: cs.surfaceVariant,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: cs.outline),
                          ),
                          child: Row(
                            children: [
                              AnimatedCheckbox(
                                checked: item.task.isCompleted,
                                color: goalColor,
                                onToggle: () async {
                                  await TaskRepository.instance
                                      .toggleComplete(item.task.id);
                                  bumpActivityTick(ref);
                                  ref.invalidate(focusTasksProvider(goalId));
                                },
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.task.text,
                                      style: tt.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      item.milestone?.title ?? '',
                                      style: tt.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              DueDateBadge(contextData: item),
                            ],
                          ),
                        ),
                      )
                          .animate()
                          .fadeIn(delay: (index * 50).ms)
                          .slideX(begin: 0.04),
                    );
                  }),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
