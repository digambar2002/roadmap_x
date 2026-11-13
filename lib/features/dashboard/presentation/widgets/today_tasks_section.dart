import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:flutter/services.dart';

import '../../../../core/models/today_task.dart';
import '../../../../shared/widgets/animated_checkbox.dart';
import '../../../../shared/widgets/due_date_badge.dart';
import '../../../analytics/providers/activity_provider.dart';
import '../../../tasks/data/task_repository.dart';
import '../../../tasks/providers/task_provider.dart';
import '../../../tasks/presentation/task_actions.dart';
import '../../../../shared/widgets/item_actions.dart';

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
    HapticFeedback.lightImpact();
    await TaskRepository.instance.toggleComplete(ctx.task.id);
    // ref throws if the widget was disposed while the write was in flight.
    if (!ref.context.mounted) return;
    bumpActivityTick(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return groupedAsync.when(
      // A task write fires several refresh signals at once. Keep showing
      // the current list while new data loads instead of swapping it for a
      // placeholder; that swap is what made the screen flicker.
      skipLoadingOnReload: true,
      loading: () => const SizedBox(height: 60),
      error: (_, __) => const SizedBox.shrink(),
      data: (data) {
        // Most urgent first: anything late, then today, then the rest of the
        // week — the same order the Today screen uses.
        final ordered = [...data.overdue, ...data.dueToday, ...data.thisWeek];
        final shown = ordered.take(maxShown).toList();
        final remaining = ordered.length - shown.length;

        // Height changes (a task added, ticked off or rescheduled) ease in
        // rather than jumping the page below.
        return AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
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
                    onPressed: () => context.push('/tasks'),
                    child: const Text('See all'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (shown.isEmpty)
                _NothingDue(onPlan: () => context.push('/tasks'))
              else ...[
                for (final ctx in shown)
                  _TaskRow(
                    taskCtx: ctx,
                    onToggle: () => _toggle(ref, ctx),
                  ),
                if (remaining > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => context.push('/tasks'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 6, horizontal: 4),
                        child: Text(
                          '+$remaining more',
                          style: tt.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ),
              ],
              // Captured tasks with no date or goal yet: a gentle nudge to
              // sort them, without crowding today's list.
              if (data.inbox.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => context.push('/tasks'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 6, horizontal: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.inbox_outlined,
                              size: 16, color: Color(0xFFA78BFA)),
                          const SizedBox(width: 6),
                          Text(
                            'Inbox · ${data.inbox.length} to sort',
                            style: tt.bodySmall?.copyWith(
                              color: const Color(0xFFA78BFA),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TaskRow extends ConsumerWidget {
  const _TaskRow({
    required this.taskCtx,
    required this.onToggle,
  });

  final TodayTaskContext taskCtx;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final task = taskCtx.task;
    final goalColor = Color(taskCtx.goal?.colorHex ?? cs.primary.toARGB32());

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ItemSwipeActions(
        itemKey: ValueKey('today-task-${task.id}'),
        radius: 12,
        onEdit: () => TaskActions.edit(context, taskCtx),
        onDelete: () => TaskActions.delete(context, ref, taskCtx),
        child: Material(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => TaskActions.edit(context, taskCtx),
            onLongPress: () => TaskActions.showMenu(context, ref, taskCtx),
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
                          '${taskCtx.goal?.name ?? 'Inbox'}',
                          style: tt.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (task.repeat != null)
                    const Padding(
                      padding: EdgeInsets.only(left: 4, right: 2),
                      child: Icon(Icons.repeat_rounded, size: 15),
                    ),
                  DueDateBadge(contextData: taskCtx),
                ],
              ),
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
