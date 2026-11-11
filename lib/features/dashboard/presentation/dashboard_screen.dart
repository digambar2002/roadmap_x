import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/models/models.dart';
import '../../../core/models/today_task.dart';
import '../../../core/services/schedule_completion_service.dart';
import '../../../core/utils/date_utils.dart';
import '../../ai_coach/providers/ai_coach_provider.dart';
import '../../analytics/providers/activity_provider.dart';
import '../../ai_goal/presentation/ai_goal_sheet.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../../habits/presentation/widgets/habit_edit_sheet.dart';
import '../../schedule/presentation/schedule_screen.dart';
import '../../schedule/providers/schedule_provider.dart';
import '../../habits/providers/habit_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../tasks/data/task_repository.dart';
import '../../tasks/providers/task_provider.dart';
import '../../today/presentation/widgets/pick_goal_tasks_sheet.dart';
import '../../premium/presentation/premium_gate.dart';

import '../../goals/presentation/widgets/create_edit_goal_sheet.dart';
import 'widgets/collapsible_briefing.dart';
import 'widgets/dashboard_header.dart';
import '../../companion/presentation/companion_card.dart';
import '../../../core/layout/adaptive_page.dart';
import '../../../core/layout/adaptive_sheet.dart';
import '../../../core/layout/breakpoints.dart';
import 'widgets/daily_habits_section.dart';
import 'widgets/today_tasks_section.dart';
import '../../../shared/widgets/item_actions.dart';

/// The Today tab: the home of the app, and only about today.
///
/// It answers one question — "what should I do now?" — in the order the day
/// is lived: habits to tick, tasks that are due, then the day's time blocks.
/// Long-term planning lives on the Goals tab and account/settings on the Me
/// tab, so neither competes for space here. Creating anything goes through the
/// single "+" button.
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
    final hasAi = ref.watch(hasAiCoachProvider);
    final todayWeekday = DateTime.now().weekday % 7;
    final scheduleAsync = ref.watch(scheduleForWeekdayProvider(todayWeekday));
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final completedScheduleAsync =
        ref.watch(scheduleCompletedUidsProvider(todayDate));

    final rawName = settingsAsync.value?.userName ?? '';
    final userName = rawName.isEmpty ? 'there' : rawName;
    final gutter = context.pageGutter;
    final gap = context.sectionGap;

    final habits = habitListAsync.valueOrNull ?? const <Habit>[];
    final hasGoals = (dashAsync.valueOrNull?.goals.isNotEmpty) ?? true;
    final isBrandNew = !hasGoals && habits.isEmpty;

    final header = DashboardHeader(
      greeting: '${AppDateUtils.greeting()}, $userName',
      date: AppDateUtils.formatDateWithDay(now),
    );

    // The companion and the perfect-day ring replace the old stat tiles:
    // one glance says how today is going and what is at stake.
    final stats = CompanionCard(streak: streakAsync.valueOrNull ?? 0);

    final todaysTasks = TodayTasksSection(groupedAsync: todayGroupedAsync);

    // The schedule only takes space on days that have one; setting it up is
    // offered from the "+" button and the Me tab instead of an empty card.
    final scheduleItems = scheduleAsync.valueOrNull ?? const <ScheduleItem>[];
    final Widget? schedule = scheduleItems.isEmpty
        ? null
        : _DashboardSection(
            title: "Today's schedule",
            action: TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: () => context.push('/schedule'),
              child: const Text('Manage'),
            ),
            child: _TodayScheduleList(
              items: scheduleItems,
              completedUids: completedScheduleAsync.valueOrNull ?? {},
              todayDate: todayDate,
            ),
          );

    final dailyHabits = DailyHabitsSection(
      habits: habits,
      checked: checkedAsync.valueOrNull ?? const <String>{},
      streak: streakAsync.valueOrNull ?? 0,
    );

    // The AI briefing is only shown to people who have set up the coach; for
    // everyone else it was a locked card taking up the bottom of the page.
    final Widget? briefing = hasAi ? const CollapsibleBriefing() : null;

    final List<Widget> mainColumn = [
      if (isBrandNew) ...[
        _GetStartedCard(
          onNewGoal: () => _createGoal(context, ref),
          onNewHabit: () => HabitEditSheet.show(context),
        ),
        SizedBox(height: gap),
      ],
      dailyHabits,
      SizedBox(height: gap),
      todaysTasks,
    ];

    final List<Widget> sideColumn = [
      if (schedule != null) schedule,
      if (schedule != null && briefing != null) SizedBox(height: gap),
      if (briefing != null) briefing,
    ];

    final Widget content = context.isExpanded && sideColumn.isNotEmpty
        ? AdaptiveColumns(
            spacing: 28,
            main: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: mainColumn,
            ),
            side: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: sideColumn,
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...mainColumn,
              for (final w in sideColumn) ...[
                if (w is! SizedBox) SizedBox(height: gap),
                if (w is! SizedBox) w,
              ],
            ],
          );

    return Scaffold(
      backgroundColor: cs.surface,
      floatingActionButton: FloatingActionButton(
        heroTag: 'today_add_fab',
        tooltip: 'Add',
        onPressed: () => _showQuickAdd(context, ref),
        child: const Icon(Icons.add_rounded),
      ),
      body: AdaptivePage.wide(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(dashboardDataProvider);
              if (hasAi) {
                await ref.read(dailyBriefingProvider.notifier).refresh();
              }
              ref.invalidate(todayTasksGroupedProvider);
              ref.invalidate(todayHabitChecksProvider);
              bumpActivityTick(ref);
            },
            child: ListView(
              padding: EdgeInsets.fromLTRB(gutter, 20, gutter, 96),
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

  Future<void> _showQuickAdd(BuildContext context, WidgetRef ref) async {
    final choice = await showAdaptiveSheet<_QuickAdd>(
      context: context,
      builder: (sheetContext) => const _QuickAddSheet(),
    );
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case _QuickAdd.goal:
        await _createGoal(context, ref);
      case _QuickAdd.aiGoal:
        await _generateWithAi(context, ref);
      case _QuickAdd.tasksForToday:
        await _pickTasks(context);
      case _QuickAdd.habit:
        HabitEditSheet.show(context);
      case _QuickAdd.routine:
        showAdaptiveSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const CreateEditScheduleSheet(),
        );
    }
  }

  Future<void> _pickTasks(BuildContext context) async {
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
                ? 'Added 1 task to today'
                : 'Added $result tasks to today',
          ),
        ),
      );
    }
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

enum _QuickAdd { goal, aiGoal, tasksForToday, habit, routine }

/// Everything that can be created, in one list, from one button.
class _QuickAddSheet extends StatelessWidget {
  const _QuickAddSheet();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    Widget item(_QuickAdd value, IconData icon, String title, String sub) =>
        ListTile(
          leading: Icon(icon),
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(sub),
          onTap: () => Navigator.pop(context, value),
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Text(
                'Add',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            item(_QuickAdd.tasksForToday, Icons.playlist_add_check_rounded,
                'Tasks for today', 'Pick from your goals or add a quick task'),
            item(_QuickAdd.habit, Icons.check_circle_outline_rounded, 'Habit',
                'Something to do every day'),
            item(_QuickAdd.goal, Icons.flag_outlined, 'Goal',
                'A bigger outcome with milestones'),
            item(_QuickAdd.aiGoal, Icons.auto_awesome_outlined, 'Goal with AI',
                'Describe it and get a full roadmap'),
            item(_QuickAdd.routine, Icons.schedule_rounded, 'Routine',
                'A recurring time block in your week'),
          ],
        ),
      ),
    );
  }
}

/// Shown only on a brand-new install, so the first screen is a clear next
/// step rather than a column of empty sections.
class _GetStartedCard extends StatelessWidget {
  const _GetStartedCard({required this.onNewGoal, required this.onNewHabit});

  final VoidCallback onNewGoal;
  final VoidCallback onNewHabit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Start your roadmap',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Set a goal to work towards, or a habit to build. Today fills in '
            'from there.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onNewGoal,
                  icon: const Icon(Icons.flag_outlined, size: 18),
                  label: const Text('Create a goal'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onNewHabit,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add a habit'),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms);
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
            // Key by uid so a State isn't reused for a different item when
            // deletions or reorders shift list positions.
            key: ValueKey(e.value.uid),
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
    super.key,
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

  @override
  void didUpdateWidget(covariant _ScheduleRow old) {
    super.didUpdateWidget(old);
    if (old.item.uid != widget.item.uid ||
        old.item.goalUid != widget.item.goalUid) {
      _linkedTasks = [];
      _loadLinkedTasks();
    }
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

    // Same rule as the Schedule screen: tap expands, long-press or ⋯ for
    // options, swipe left for Edit / Delete.
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ItemSwipeActions(
        itemKey: ValueKey('today-schedule-${widget.item.uid}'),
        radius: 12,
        onEdit: () => editScheduleItem(context, widget.item),
        onDelete: () => deleteScheduleItem(context, widget.item),
        child: GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          onLongPress: () => showItemActions(context,
              title: widget.item.label,
              actions: scheduleItemActions(context, widget.item)),
          child: Container(
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
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
                                _expanded
                                    ? Icons.expand_less
                                    : Icons.expand_more,
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
                                            final g = data.goals.firstWhere(
                                                (g) =>
                                                    g.uid ==
                                                    widget.item.goalUid);
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
        ),
      ),
    );
  }
}
