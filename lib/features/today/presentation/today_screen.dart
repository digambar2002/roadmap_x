import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/layout/adaptive_page.dart';
import '../../../core/layout/adaptive_sheet.dart';
import '../../../core/models/today_task.dart';
import '../../../shared/widgets/animated_checkbox.dart';
import '../../../shared/widgets/due_date_badge.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../analytics/providers/activity_provider.dart';
import '../../tasks/data/task_repository.dart';
import '../../tasks/providers/task_provider.dart';
import '../providers/today_provider.dart';
import 'widgets/pick_goal_tasks_sheet.dart';

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
      body: AdaptivePage(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header (Aligned with page measure) ───────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Today',
                        style: tt.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.playlist_add_rounded),
                      tooltip: 'Pick Tasks from Goals',
                      onPressed: () => _openPickTasks(context, ref),
                    ),
                  ],
                ),
              ),

              // ── Content ──────────────────────────────────────────────
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(todayTasksGroupedProvider);
                    bumpActivityTick(ref);
                  },
                  child: groupedAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => ListView(
                      children: [Center(child: Text('Error: $e'))],
                    ),
                    data: (data) {
                      if (data.totalCount == 0) {
                        return ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(24),
                          children: [
                            EmptyState(
                              emoji: '✨',
                              title: 'All caught up',
                              subtitle:
                                  'No overdue or upcoming tasks right now.',
                              buttonLabel: '+ Pick Tasks from Goals',
                              onButton: () => _openPickTasks(context, ref),
                            ),
                          ],
                        );
                      }

                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
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
                                onScheduleToday: () =>
                                    _scheduleForToday(ref, ctx),
                                onPostponeTomorrow: () =>
                                    _postponeToTomorrow(ref, ctx),
                                onClearDueDate: () =>
                                    _clearDueDate(ref, ctx),
                                onChangeDueDate: () =>
                                    _pickCustomDueDate(context, ref, ctx),
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
                                onPostponeTomorrow: () =>
                                    _postponeToTomorrow(ref, ctx),
                                onClearDueDate: () =>
                                    _clearDueDate(ref, ctx),
                                onChangeDueDate: () =>
                                    _pickCustomDueDate(context, ref, ctx),
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
                                onScheduleToday: () =>
                                    _scheduleForToday(ref, ctx),
                                onPostponeTomorrow: () =>
                                    _postponeToTomorrow(ref, ctx),
                                onClearDueDate: () =>
                                    _clearDueDate(ref, ctx),
                                onChangeDueDate: () =>
                                    _pickCustomDueDate(context, ref, ctx),
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
                                onScheduleToday: () =>
                                    _scheduleForToday(ref, ctx),
                                onPostponeTomorrow: () =>
                                    _postponeToTomorrow(ref, ctx),
                                onChangeDueDate: () =>
                                    _pickCustomDueDate(context, ref, ctx),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF5B9CF6), Color(0xFFA78BFA)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF5B9CF6).withOpacity(0.35),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          heroTag: 'today_fab',
          elevation: 0,
          backgroundColor: Colors.transparent,
          onPressed: () => _openPickTasks(context, ref),
          icon: const Icon(Icons.playlist_add_rounded, color: Colors.white, size: 20),
          label: const Text(
            'Pick Tasks',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openPickTasks(BuildContext context, WidgetRef ref) async {
    final result = await showAdaptiveSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PickGoalTasksSheet(),
    );

    if (result != null && result > 0 && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result == 1
                ? '1 task added to Today'
                : '$result tasks added to Today',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _toggleTask(WidgetRef ref, TodayTaskContext ctx) async {
    await TaskRepository.instance.toggleComplete(ctx.task.id);
    if (!ref.context.mounted) return;
    bumpActivityTick(ref);
    ref.invalidate(todayTasksGroupedProvider);
  }

  Future<void> _scheduleForToday(WidgetRef ref, TodayTaskContext ctx) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await TaskRepository.instance.setDueDate(ctx.task.id, today);
    if (!ref.context.mounted) return;
    bumpActivityTick(ref);
    ref.invalidate(todayTasksGroupedProvider);
  }

  Future<void> _postponeToTomorrow(WidgetRef ref, TodayTaskContext ctx) async {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    await TaskRepository.instance.setDueDate(ctx.task.id, tomorrow);
    if (!ref.context.mounted) return;
    bumpActivityTick(ref);
    ref.invalidate(todayTasksGroupedProvider);
  }

  Future<void> _clearDueDate(WidgetRef ref, TodayTaskContext ctx) async {
    await TaskRepository.instance.setDueDate(ctx.task.id, null);
    if (!ref.context.mounted) return;
    bumpActivityTick(ref);
    ref.invalidate(todayTasksGroupedProvider);
  }

  Future<void> _pickCustomDueDate(
    BuildContext context,
    WidgetRef ref,
    TodayTaskContext ctx,
  ) async {
    final now = DateTime.now();
    final initial = ctx.dueDate ?? now;
    var firstDate = now.subtract(const Duration(days: 365));
    if (initial.isBefore(firstDate)) firstDate = initial;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (picked != null) {
      await TaskRepository.instance.setDueDate(ctx.task.id, picked);
      if (!ref.context.mounted) return;
      bumpActivityTick(ref);
      ref.invalidate(todayTasksGroupedProvider);
    }
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
            const Color(0xFF5B9CF6).withValues(alpha: 0.12),
            const Color(0xFF34D399).withValues(alpha: 0.08),
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
    );
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
              color: color.withValues(alpha: 0.12),
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
  final VoidCallback? onScheduleToday;
  final VoidCallback? onPostponeTomorrow;
  final VoidCallback? onClearDueDate;
  final VoidCallback? onChangeDueDate;
  final bool showDueDate;

  const _TodayTaskTile({
    required this.taskCtx,
    required this.onToggle,
    required this.onTap,
    this.onScheduleToday,
    this.onPostponeTomorrow,
    this.onClearDueDate,
    this.onChangeDueDate,
    this.showDueDate = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final goalColor =
        Color(taskCtx.goal?.colorHex ?? cs.primary.toARGB32());
    final task = taskCtx.task;
    final isDueToday = taskCtx.isDueToday;

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
                        style:
                            tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (!isDueToday && onScheduleToday != null) ...[
                  IconButton(
                    icon: const Icon(Icons.wb_sunny_outlined, size: 19),
                    tooltip: 'Move to Today',
                    color: const Color(0xFF5B9CF6),
                    visualDensity: VisualDensity.compact,
                    onPressed: onScheduleToday,
                  ),
                ],
                if (showDueDate || taskCtx.isOverdue)
                  DueDateBadge(contextData: taskCtx),
                // Revert / Options Menu
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                  tooltip: 'Task options',
                  padding: EdgeInsets.zero,
                  onSelected: (value) {
                    switch (value) {
                      case 'today':
                        onScheduleToday?.call();
                        break;
                      case 'tomorrow':
                        onPostponeTomorrow?.call();
                        break;
                      case 'clear':
                        onClearDueDate?.call();
                        break;
                      case 'date':
                        onChangeDueDate?.call();
                        break;
                      case 'goal':
                        onTap();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    if (!isDueToday && onScheduleToday != null)
                      const PopupMenuItem(
                        value: 'today',
                        child: Row(
                          children: [
                            Icon(Icons.wb_sunny_rounded,
                                size: 18, color: Color(0xFF5B9CF6)),
                            SizedBox(width: 10),
                            Text('Move to Today'),
                          ],
                        ),
                      ),
                    if (onPostponeTomorrow != null)
                      const PopupMenuItem(
                        value: 'tomorrow',
                        child: Row(
                          children: [
                            Icon(Icons.next_plan_outlined, size: 18),
                            SizedBox(width: 10),
                            Text('Postpone to Tomorrow'),
                          ],
                        ),
                      ),
                    if (task.dueDate != null && onClearDueDate != null)
                      PopupMenuItem(
                        value: 'clear',
                        child: Row(
                          children: [
                            Icon(Icons.undo_rounded,
                                size: 18, color: cs.error),
                            const SizedBox(width: 10),
                            Text(
                              isDueToday
                                  ? 'Remove from Today'
                                  : 'Clear Due Date',
                              style: TextStyle(color: cs.error),
                            ),
                          ],
                        ),
                      ),
                    if (onChangeDueDate != null)
                      const PopupMenuItem(
                        value: 'date',
                        child: Row(
                          children: [
                            Icon(Icons.edit_calendar_rounded, size: 18),
                            SizedBox(width: 10),
                            Text('Change Due Date...'),
                          ],
                        ),
                      ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'goal',
                      child: Row(
                        children: [
                          Icon(Icons.arrow_forward_rounded, size: 18),
                          SizedBox(width: 10),
                          Text('Open Goal Details'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
