import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/models/today_task.dart';
import '../../../shared/widgets/animated_checkbox.dart';
import '../../../shared/widgets/due_date_badge.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../analytics/providers/activity_provider.dart';
import '../../tasks/data/task_repository.dart';
import '../../tasks/providers/task_provider.dart';
import '../providers/today_provider.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final summaryAsync = ref.watch(todayDataProvider);
    final groupedAsync = ref.watch(todayTasksGroupedProvider);

    return Scaffold(
      backgroundColor: cs.background,
      appBar: AppBar(
        title: Text('Today',
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        backgroundColor: cs.background,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(todayTasksGroupedProvider);
          bumpActivityTick(ref);
        },
        child: groupedAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [Center(child: Text('Error: $e'))],
          ),
          data: (data) {
            if (data.totalCount == 0) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: const [
                  EmptyState(
                    emoji: '✨',
                    title: 'All caught up',
                    subtitle: 'No overdue or upcoming tasks right now.',
                  ),
                ],
              );
            }

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                summaryAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (summary) => _SummaryStrip(data: summary),
                ),
                const SizedBox(height: 16),
                if (data.overdue.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'Overdue',
                    color: cs.error,
                    count: data.overdue.length,
                  ),
                  ...data.overdue.map(
                    (ctx) => _TodayTaskTile(
                      taskCtx: ctx,
                      onToggle: () => _toggleTask(ref, ctx),
                      onTap: () => _openGoal(context, ctx),
                      showDueDate: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (data.dueToday.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'Due Today',
                    color: const Color(0xFF5B9CF6),
                    count: data.dueToday.length,
                  ),
                  ...data.dueToday.map(
                    (ctx) => _TodayTaskTile(
                      taskCtx: ctx,
                      onToggle: () => _toggleTask(ref, ctx),
                      onTap: () => _openGoal(context, ctx),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (data.thisWeek.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'This Week',
                    color: const Color(0xFF34D399),
                    count: data.thisWeek.length,
                  ),
                  ...data.thisWeek.map(
                    (ctx) => _TodayTaskTile(
                      taskCtx: ctx,
                      onToggle: () => _toggleTask(ref, ctx),
                      onTap: () => _openGoal(context, ctx),
                      showDueDate: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (data.noDueDate.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'Up Next',
                    color: cs.onSurfaceVariant,
                    count: data.noDueDate.length,
                  ),
                  ...data.noDueDate.map(
                    (ctx) => _TodayTaskTile(
                      taskCtx: ctx,
                      onToggle: () => _toggleTask(ref, ctx),
                      onTap: () => _openGoal(context, ctx),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _toggleTask(WidgetRef ref, TodayTaskContext ctx) async {
    await TaskRepository.instance.toggleComplete(ctx.task.id);
    bumpActivityTick(ref);
    ref.invalidate(todayTasksGroupedProvider);
  }

  void _openGoal(BuildContext context, TodayTaskContext ctx) {
    final goalId = ctx.goal?.id;
    if (goalId != null) context.push('/goals/$goalId');
  }
}

class _SummaryStrip extends StatelessWidget {
  final TodayData data;
  const _SummaryStrip({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF5B9CF6).withOpacity(0.12),
            const Color(0xFF34D399).withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline),
      ),
      child: Row(
        children: [
          _Metric(title: 'Action', value: data.total.toString()),
          _Metric(title: 'Overdue', value: data.overdue.toString()),
          _Metric(title: 'Today', value: data.dueToday.toString()),
          _Metric(title: 'Week', value: data.dueThisWeek.toString()),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms);
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;
  final int count;

  const _SectionHeader({
    required this.title,
    required this.color,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayTaskTile extends StatelessWidget {
  final TodayTaskContext taskCtx;
  final VoidCallback onToggle;
  final VoidCallback onTap;
  final bool showDueDate;

  const _TodayTaskTile({
    required this.taskCtx,
    required this.onToggle,
    required this.onTap,
    this.showDueDate = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final goalColor = Color(taskCtx.goal?.colorHex ?? cs.primary.value);
    final task = taskCtx.task;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cs.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outline),
            ),
            child: Row(
              children: [
                AnimatedCheckbox(
                  checked: task.isCompleted,
                  color: goalColor,
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
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${taskCtx.goal?.emoji ?? ''} ${taskCtx.goal?.name ?? 'Unlinked'} · ${taskCtx.milestone?.title ?? ''}',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (showDueDate || taskCtx.isOverdue)
                  DueDateBadge(contextData: taskCtx),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 200.ms).slideX(begin: 0.03);
  }
}

class _Metric extends StatelessWidget {
  final String title;
  final String value;
  const _Metric({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(title, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
