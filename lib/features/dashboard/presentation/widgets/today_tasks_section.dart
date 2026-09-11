import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/models/today_task.dart';
import '../../../../shared/widgets/animated_checkbox.dart';
import '../../../../shared/widgets/due_date_badge.dart';
import '../../../analytics/providers/activity_provider.dart';
import '../../../tasks/data/task_repository.dart';
import '../../../tasks/providers/task_provider.dart';

/// Today's actual work, on the dashboard, ahead of the schedule.
///
/// This replaced a "Next up" card that showed a single task and could only be
/// tapped through to another screen. The work due today is the thing most
/// worth acting on from the home page, so it is shown as a real list that can
/// be ticked off in place.
class TodayTasksSection extends ConsumerWidget {
  const TodayTasksSection({super.key, required this.groupedAsync});

  final AsyncValue<TodayTasksData> groupedAsync;

  /// Enough to be useful, few enough that the schedule below stays reachable.
  static const int maxShown = 5;

  Future<void> _toggle(WidgetRef ref, TodayTaskContext ctx) async {
    await TaskRepository.instance.toggleComplete(ctx.task.id);
    // ref throws if the widget was disposed while the write was in flight.
    if (!ref.context.mounted) return;
    bumpActivityTick(ref);
    ref.invalidate(todayTasksGroupedProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return groupedAsync.when(
      loading: () => const SizedBox(height: 60),
      error: (_, __) => const SizedBox.shrink(),
      data: (data) {
        // Most urgent first: anything late, then today, then the rest of the
        // week — the same order the Today screen uses.
        final ordered = [...data.overdue, ...data.dueToday, ...data.thisWeek];
        final shown = ordered.take(maxShown).toList();
        final remaining = ordered.length - shown.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  "Today's tasks",
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (data.overdue.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.error.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${data.overdue.length} overdue',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: cs.error,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () => context.go('/today'),
                  child: const Text('See all'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (shown.isEmpty)
              _NothingDue(onPlan: () => context.go('/today'))
            else ...[
              for (final ctx in shown)
                _TaskRow(
                  taskCtx: ctx,
                  onToggle: () => _toggle(ref, ctx),
                  onOpen: () {
                    final goalId = ctx.goal?.id;
                    if (goalId != null) context.push('/goals/$goalId');
                  },
                ),
              if (remaining > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => context.go('/today'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 6, horizontal: 4),
                      child: Text(
                        '+$remaining more',
                        style:
                            tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.taskCtx,
    required this.onToggle,
    required this.onOpen,
  });

  final TodayTaskContext taskCtx;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final task = taskCtx.task;
    final goalColor = Color(taskCtx.goal?.colorHex ?? cs.primary.toARGB32());

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onOpen,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outline),
            ),
            child: Row(
              children: [
                AnimatedCheckbox(
                  checked: task.isCompleted,
                  color: goalColor,
                  size: 20,
                  onToggle: onToggle,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.text,
                        style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          decoration: task.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${taskCtx.goal?.emoji ?? ''} '
                        '${taskCtx.goal?.name ?? 'Unlinked'}',
                        style:
                            tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                DueDateBadge(contextData: taskCtx),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NothingDue extends StatelessWidget {
  const _NothingDue({required this.onPlan});

  final VoidCallback onPlan;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onPlan,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outline),
          color: cs.surfaceContainerHighest,
        ),
        child: Row(
          children: [
            const Text('✅', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Nothing due — you are clear for today',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
