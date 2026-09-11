import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/models/habit_icons.dart';
import '../../../core/models/models.dart';
import '../../../core/models/today_task.dart';
import '../../../core/services/schedule_completion_service.dart';
import '../../../core/utils/date_utils.dart';
import '../../../shared/widgets/animated_checkbox.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../ai_coach/providers/ai_coach_provider.dart';
import '../../analytics/providers/activity_provider.dart';
import '../../ai_goal/presentation/ai_goal_sheet.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../../schedule/providers/schedule_provider.dart';
import '../../habits/providers/habit_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../tasks/data/task_repository.dart';
import '../../tasks/providers/task_provider.dart';
import '../../premium/presentation/premium_gate.dart';

import '../../goals/presentation/widgets/create_edit_goal_sheet.dart';
import 'widgets/collapsible_briefing.dart';
import 'widgets/dashboard_header.dart';
import 'widgets/focus_goals_section.dart';
import 'widgets/stat_strip.dart';
import '../../../core/layout/adaptive_page.dart';
import '../../../core/layout/adaptive_sheet.dart';
import '../../../core/layout/breakpoints.dart';
import '../../premium/presentation/account_button.dart';
import 'widgets/today_tasks_section.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final settingsAsync = ref.watch(settingsProvider);
    final dashAsync = ref.watch(dashboardDataProvider);
    final todayGroupedAsync = ref.watch(todayTasksGroupedProvider);
    final habitListAsync = ref.watch(habitsProvider);
    final checkedAsync = ref.watch(todayHabitChecksProvider);
    final streakAsync = ref.watch(habitStreakProvider);
    final todayWeekday = DateTime.now().weekday % 7;
    final scheduleAsync = ref.watch(scheduleForWeekdayProvider(todayWeekday));
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final completedScheduleAsync =
        ref.watch(scheduleCompletedUidsProvider(todayDate));

    final userName = settingsAsync.value?.userName ?? 'there';
    final grouped = todayGroupedAsync.valueOrNull;
    final gutter = context.pageGutter;
    final gap = context.sectionGap;

    final header = DashboardHeader(
      greeting: '${AppDateUtils.greeting()}, $userName',
      date: AppDateUtils.formatDateWithDay(now),
      onNewGoal: () => _createGoal(context, ref),
      onGenerateWithAi: () => _generateWithAi(context, ref),
      trailing: const AccountButton(),
    );

    final stats = StatStrip(
      stats: [
        DashboardStat(
          value: '${grouped?.overdue.length ?? 0}',
          label: 'Overdue',
          icon: Icons.error_outline_rounded,
          color: cs.error,
          // Zero overdue is good news, so it is not painted red.
          isMuted: (grouped?.overdue.length ?? 0) == 0,
          onTap: () => context.go('/today'),
        ),
        DashboardStat(
          value: '${grouped?.dueToday.length ?? 0}',
          label: 'Today',
          icon: Icons.today_rounded,
          color: const Color(0xFF5B9CF6),
          isMuted: (grouped?.dueToday.length ?? 0) == 0,
          onTap: () => context.go('/today'),
        ),
        DashboardStat(
          value:
              '${((dashAsync.valueOrNull?.overallPercent ?? 0) * 100).round()}%',
          label: 'Progress',
          icon: Icons.trending_up_rounded,
          color: const Color(0xFF34D399),
          onTap: () => context.go('/analytics'),
        ),
        DashboardStat(
          value: '${streakAsync.valueOrNull ?? 0}',
          label: 'Streak',
          icon: Icons.local_fire_department_rounded,
          color: const Color(0xFFF59E0B),
          isMuted: (streakAsync.valueOrNull ?? 0) == 0,
          onTap: () => context.go('/analytics'),
        ),
      ],
    );

    final goals = dashAsync.when(
      loading: () => const SizedBox(height: 80),
      error: (error, _) => Text('Error: $error'),
      data: (data) => data.goals.isEmpty
          ? EmptyState(
              emoji: '🎯',
              title: 'No goals yet',
              subtitle: 'Create one to start tracking your progress.',
              buttonLabel: 'New goal',
              onButton: () => _createGoal(context, ref),
            )
          : FocusGoalsSection(data: data),
    );

    final todaysTasks = TodayTasksSection(groupedAsync: todayGroupedAsync);

    final schedule = _DashboardSection(
      title: "Today's schedule",
      action: TextButton(
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        onPressed: () => context.go('/schedule'),
        child: const Text('See all'),
      ),
      child: scheduleAsync.when(
        loading: () => const SizedBox(height: 60),
        error: (_, __) => const SizedBox.shrink(),
        data: (items) => items.isEmpty
            ? EmptyState(
                emoji: '📅',
                title: 'No schedule for today',
                subtitle: 'Add daily routines in the Schedule tab.',
                buttonLabel: 'Go to Schedule',
                onButton: () => context.go('/schedule'),
              )
            : _TodayScheduleList(
                items: items,
                completedUids: completedScheduleAsync.valueOrNull ?? {},
                todayDate: todayDate,
              ),
      ),
    );

    final nonNegotiables = _NonNegotiablesWidget(
      habits: habitListAsync.valueOrNull ?? const <Habit>[],
      checked: checkedAsync.valueOrNull ?? const <String>{},
      streak: streakAsync.valueOrNull ?? 0,
    );

    const briefing = CollapsibleBriefing();

    // Wide windows read the sections as two columns rather than one very long
    // one: the day's own state (habits, briefing) sits beside the work itself
    // instead of being buried a screen below it.
    final Widget content = context.isExpanded
        ? AdaptiveColumns(
            spacing: 28,
            main: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                goals,
                SizedBox(height: gap),
                todaysTasks,
                SizedBox(height: gap),
                schedule,
              ],
            ),
            side: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [nonNegotiables, SizedBox(height: gap), briefing],
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              goals,
              SizedBox(height: gap),
              todaysTasks,
              SizedBox(height: gap),
              schedule,
              SizedBox(height: gap),
              nonNegotiables,
              SizedBox(height: gap),
              briefing,
            ],
          );

    return Scaffold(
      backgroundColor: cs.surface,
      body: AdaptivePage.wide(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(dashboardDataProvider);
              await ref.read(dailyBriefingProvider.notifier).refresh();
              ref.invalidate(todayTasksGroupedProvider);
              ref.invalidate(todayHabitChecksProvider);
              bumpActivityTick(ref);
            },
            child: ListView(
              padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 40),
              children: [
                header,
                SizedBox(height: gap * 0.7),
                stats,
                SizedBox(height: gap),
                content,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _createGoal(BuildContext context, WidgetRef ref) async {
    if (!await PremiumGate.ensureGoalSlot(context, ref)) return;
    if (!context.mounted) return;
    showAdaptiveSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CreateEditGoalSheet(),
    );
  }

  Future<void> _generateWithAi(BuildContext context, WidgetRef ref) async {
    if (!await PremiumGate.ensureAi(context, ref)) return;
    if (!context.mounted) return;
    final goalId = await showAiGoalSheet(context);
    if (!context.mounted || goalId == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🎉 Goal created! Start working on it.')),
    );
    context.go('/goals/$goalId');
  }
}

/// Section heading with an optional trailing action.
class _DashboardSection extends StatelessWidget {
  const _DashboardSection({
    required this.title,
    required this.child,
    this.action,
  });

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (action != null) action!,
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _TodayScheduleList extends ConsumerWidget {
  final List<ScheduleItem> items;
  final Set<String> completedUids;
  final DateTime todayDate;
  const _TodayScheduleList({
    required this.items,
    required this.completedUids,
    required this.todayDate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: items.asMap().entries.map((e) {
          return _ScheduleRow(
            item: e.value,
            isCompleted: completedUids.contains(e.value.uid),
            todayDate: todayDate,
          ).animate().fadeIn(delay: (e.key * 40).ms).slideX(begin: -0.05);
        }).toList(),
      ),
    );
  }
}

class _ScheduleRow extends ConsumerStatefulWidget {
  final ScheduleItem item;
  final bool isCompleted;
  final DateTime todayDate;
  const _ScheduleRow({
    required this.item,
    required this.isCompleted,
    required this.todayDate,
  });

  @override
  ConsumerState<_ScheduleRow> createState() => _ScheduleRowState();
}

class _ScheduleRowState extends ConsumerState<_ScheduleRow> {
  bool _expanded = false;
  List<TodayTaskContext> _linkedTasks = [];

  @override
  void initState() {
    super.initState();
    _loadLinkedTasks();
  }

  Future<void> _loadLinkedTasks() async {
    if (widget.item.goalUid.isEmpty) return;
    final tasks = await TaskRepository.instance
        .getNextTasksForGoal(widget.item.goalUid, limit: 3);
    if (mounted) setState(() => _linkedTasks = tasks);
  }

  Future<void> _toggleDone(bool? value) async {
    await ScheduleCompletionService.instance.setCompleted(
      widget.todayDate,
      widget.item.uid,
      value ?? false,
    );
    ref.invalidate(scheduleCompletedUidsProvider(widget.todayDate));
    bumpActivityTick(ref);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    // Resolve goal color
    final goalsAsync = ref.watch(dashboardDataProvider);
    Color accentColor = cs.primary;
    String? goalName;

    if (widget.item.goalUid.isNotEmpty) {
      goalsAsync.whenData((data) {
        try {
          final g = data.goals.firstWhere((g) => g.uid == widget.item.goalUid);
          accentColor = Color(g.colorHex);
          goalName = g.name;
        } catch (_) {}
      });
    }

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: cs.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outline),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Color bar
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Checkbox(
                            value: widget.isCompleted,
                            onChanged: _toggleDone,
                          ),
                          // Time badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: accentColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              widget.item.time,
                              style: TextStyle(
                                fontFamily: 'JetBrains Mono',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: accentColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.isCompleted
                                  ? '✓ ${widget.item.label}'
                                  : widget.item.label,
                              style: tt.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                                decoration: widget.isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                          Icon(
                            _expanded ? Icons.expand_less : Icons.expand_more,
                            size: 18,
                            color: cs.onSurfaceVariant,
                          ),
                        ],
                      ),
                      if (_expanded) ...[
                        const SizedBox(height: 6),
                        if (widget.item.detail.isNotEmpty)
                          Text(widget.item.detail, style: tt.bodySmall),
                        if (goalName != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.flag_outlined,
                                  size: 12, color: accentColor),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(goalName!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: accentColor,
                                      fontWeight: FontWeight.w500,
                                    )),
                              ),
                              if (widget.item.goalUid.isNotEmpty)
                                TextButton(
                                  onPressed: () {
                                    goalsAsync.whenData((data) {
                                      try {
                                        final g = data.goals.firstWhere((g) =>
                                            g.uid == widget.item.goalUid);
                                        context.push('/focus/${g.id}');
                                      } catch (_) {}
                                    });
                                  },
                                  child: const Text('Focus'),
                                ),
                            ],
                          ),
                        ],
                        if (_linkedTasks.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          ..._linkedTasks.map(
                            (ctx) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '• ${ctx.task.text}',
                                style: tt.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Non-negotiables ───────────────────────────────────────

class _NonNegotiablesWidget extends ConsumerWidget {
  final List<Habit> habits;
  final Set<String> checked;
  final int streak;
  const _NonNegotiablesWidget({
    required this.habits,
    required this.checked,
    required this.streak,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final doneCount = habits.where((h) => checked.contains(h.uid)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Non-negotiables',
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (habits.isNotEmpty)
              _Pill(label: '$doneCount/${habits.length}', color: cs.primary),
            if (streak > 0) ...[
              const SizedBox(width: 6),
              _Pill(label: '🔥 $streak', color: const Color(0xFF34D399)),
            ],
            IconButton(
              tooltip: 'Manage habits',
              visualDensity: VisualDensity.compact,
              onPressed: () => context.push('/habits'),
              icon: Icon(Icons.tune_rounded, size: 18, color: cs.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (habits.isEmpty)
          _AddHabitsPrompt(onTap: () => context.push('/habits'))
        else
          LayoutBuilder(
            builder: (context, constraints) {
              // Two per row once there is width for it; one when narrow, so a
              // long habit name is not clipped to nothing.
              final columns = constraints.maxWidth < 360 ? 1 : 2;
              return GridView.count(
                crossAxisCount: columns,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: columns == 1 ? 6.2 : 2.8,
                children: [
                  for (final habit in habits)
                    _HabitTile(
                      habit: habit,
                      checked: checked.contains(habit.uid),
                      onToggle: () => ref
                          .read(todayHabitChecksProvider.notifier)
                          .toggle(habit.uid),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _HabitTile extends StatelessWidget {
  const _HabitTile({
    required this.habit,
    required this.checked,
    required this.onToggle,
  });

  final Habit habit;
  final bool checked;
  final VoidCallback onToggle;

  static const _done = Color(0xFF34D399);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Material(
      color: checked
          ? _done.withValues(alpha: 0.08)
          : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: checked ? _done.withValues(alpha: 0.4) : cs.outline,
            ),
          ),
          child: Row(
            children: [
              Icon(
                HabitIcons.resolve(habit.iconKey),
                size: 18,
                color: checked ? _done : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  habit.label.isEmpty ? 'Unnamed habit' : habit.label,
                  style: tt.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: habit.label.isEmpty
                        ? cs.onSurfaceVariant
                        : cs.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IgnorePointer(
                child: AnimatedCheckbox(
                  checked: checked,
                  color: _done,
                  size: 20,
                  onToggle: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddHabitsPrompt extends StatelessWidget {
  const _AddHabitsPrompt({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outline),
          color: cs.surfaceContainerHighest,
        ),
        child: Row(
          children: [
            Icon(Icons.add_circle_outline_rounded, color: cs.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Add the few things you want to do every day',
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
