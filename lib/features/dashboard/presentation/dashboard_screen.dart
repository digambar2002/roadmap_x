import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/models/models.dart';
import '../../../core/models/today_task.dart';
import '../../../core/services/schedule_completion_service.dart';
import '../../../core/utils/date_utils.dart';
import '../../../shared/widgets/animated_checkbox.dart';
import '../../../shared/widgets/due_date_badge.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../ai_coach/providers/ai_coach_provider.dart';
import '../../analytics/providers/activity_provider.dart';
import '../../ai_goal/presentation/ai_goal_sheet.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../../schedule/providers/schedule_provider.dart';
import '../../settings/providers/habit_checkin_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../tasks/data/task_repository.dart';
import '../../tasks/providers/task_provider.dart';
import '../../premium/presentation/premium_gate.dart';

import '../../goals/presentation/widgets/create_edit_goal_sheet.dart';
import 'widgets/collapsible_briefing.dart';
import 'widgets/dashboard_header.dart';
import 'widgets/focus_goals_section.dart';
import 'widgets/stat_strip.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final settingsAsync = ref.watch(settingsProvider);
    final dashAsync = ref.watch(dashboardDataProvider);
    final todayGroupedAsync = ref.watch(todayTasksGroupedProvider);
    final habitsAsync = ref.watch(todayHabitChecksProvider);
    final streakAsync = ref.watch(habitStreakProvider);
    final todayWeekday = DateTime.now().weekday % 7;
    final scheduleAsync = ref.watch(scheduleForWeekdayProvider(todayWeekday));
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final completedScheduleAsync =
        ref.watch(scheduleCompletedUidsProvider(todayDate));

    final userName = settingsAsync.value?.userName ?? 'there';
    final grouped = todayGroupedAsync.valueOrNull;
    final dash = dashAsync.valueOrNull;

    final overdue = grouped?.overdue.length ?? 0;
    final dueToday = grouped?.dueToday.length ?? 0;
    final streak = streakAsync.valueOrNull ?? 0;
    final percent = dash?.overallPercent ?? 0;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(dashboardDataProvider);
            await ref.read(dailyBriefingProvider.notifier).refresh();
            ref.invalidate(todayTasksGroupedProvider);
            ref.invalidate(todayHabitChecksProvider);
            bumpActivityTick(ref);
          },
          child: CustomScrollView(
            slivers: [
              // ── Header ─────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: DashboardHeader(
                    greeting: '${AppDateUtils.greeting()}, $userName',
                    date: AppDateUtils.formatDateWithDay(now),
                    onNewGoal: () => _createGoal(context, ref),
                    onGenerateWithAi: () => _generateWithAi(context, ref),
                  ),
                ).animate().fadeIn(duration: 250.ms),
              ),

              // ── Headline numbers ───────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: StatStrip(
                    stats: [
                      DashboardStat(
                        value: '$overdue',
                        label: 'Overdue',
                        icon: Icons.error_outline_rounded,
                        color: cs.error,
                        // Zero overdue is good news, so it is not painted red.
                        isMuted: overdue == 0,
                        onTap: () => context.go('/today'),
                      ),
                      DashboardStat(
                        value: '$dueToday',
                        label: 'Today',
                        icon: Icons.today_rounded,
                        color: const Color(0xFF5B9CF6),
                        isMuted: dueToday == 0,
                        onTap: () => context.go('/today'),
                      ),
                      DashboardStat(
                        value: '${(percent * 100).round()}%',
                        label: 'Progress',
                        icon: Icons.trending_up_rounded,
                        color: const Color(0xFF34D399),
                        onTap: () => context.go('/analytics'),
                      ),
                      DashboardStat(
                        value: '$streak',
                        label: 'Streak',
                        icon: Icons.local_fire_department_rounded,
                        color: const Color(0xFFF59E0B),
                        isMuted: streak == 0,
                        onTap: () => context.go('/analytics'),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 60.ms),
              ),

              // ── Goals, led by Focus ────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: dashAsync.when(
                    loading: () => const SizedBox(height: 80),
                    error: (error, _) => Text('Error: $error'),
                    data: (data) => data.goals.isEmpty
                        ? EmptyState(
                            emoji: '🎯',
                            title: 'No goals yet',
                            subtitle:
                                'Create one to start tracking your progress.',
                            buttonLabel: 'New goal',
                            onButton: () => _createGoal(context, ref),
                          )
                        : FocusGoalsSection(data: data),
                  ),
                ).animate().fadeIn(delay: 100.ms),
              ),

              // ── Next up ────────────────────────────────────
              SliverToBoxAdapter(
                child: _TodayTasksPreview(groupedAsync: todayGroupedAsync),
              ),

              // ── Today's schedule ───────────────────────────
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text("Today's schedule",
                                style: tt.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700)),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            onPressed: () => context.go('/schedule'),
                            child: const Text('See all'),
                          ),
                        ],
                      ),
                    ),
                    scheduleAsync.when(
                      loading: () => const SizedBox(height: 60),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (items) => items.isEmpty
                          ? Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              child: EmptyState(
                                emoji: '📅',
                                title: 'No schedule for today',
                                subtitle:
                                    'Add daily routines in the Schedule tab.',
                                buttonLabel: 'Go to Schedule',
                                onButton: () => context.go('/schedule'),
                              ),
                            )
                          : _TodayScheduleList(
                              items: items,
                              completedUids:
                                  completedScheduleAsync.valueOrNull ?? {},
                              todayDate: todayDate,
                            ),
                    ),
                  ],
                ).animate().fadeIn(delay: 150.ms),
              ),

              // ── Non-negotiables ────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: settingsAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (s) => _NonNegotiablesWidget(
                      items: s.nonNegotiables,
                      checks: habitsAsync.valueOrNull ?? List.filled(4, false),
                      streak: streak,
                    ),
                  ),
                ).animate().fadeIn(delay: 200.ms),
              ),

              // ── AI briefing, last and closed by default ────
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 24, 20, 32),
                  child: CollapsibleBriefing(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createGoal(BuildContext context, WidgetRef ref) async {
    if (!await PremiumGate.ensureGoalSlot(context, ref)) return;
    if (!context.mounted) return;
    showModalBottomSheet(
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

class _TodayTasksPreview extends StatelessWidget {
  final AsyncValue<TodayTasksData> groupedAsync;
  const _TodayTasksPreview({required this.groupedAsync});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: groupedAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
        data: (data) {
          final first = data.overdue.isNotEmpty
              ? data.overdue.first
              : data.dueToday.isNotEmpty
                  ? data.dueToday.first
                  : data.thisWeek.isNotEmpty
                      ? data.thisWeek.first
                      : null;
          if (first == null) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Next up',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  title: Text(first.task.text),
                  subtitle: Text(first.goal?.name ?? 'Unlinked'),
                  trailing: DueDateBadge(contextData: first),
                  onTap: () => context.push('/today'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Overall progress card ─────────────────────────────────

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
          )
              .animate()
              .fadeIn(delay: (e.key * 40).ms)
              .slideX(begin: -0.05);
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
                              style: tt.bodyMedium
                                  ?.copyWith(
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
                                        final g = data.goals.firstWhere(
                                            (g) => g.uid == widget.item.goalUid);
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
  final List<String> items;
  final List<bool> checks;
  final int streak;
  const _NonNegotiablesWidget({
    required this.items,
    required this.checks,
    required this.streak,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final doneCount = checks.where((c) => c).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Non-Negotiables',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$doneCount/4',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
            ),
            if (streak > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF34D399).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '🔥 $streak',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF34D399),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.8,
          children: items.asMap().entries.map((e) {
            final icons = ['💪', '🧠', '📖', '✅'];
            final checked = e.key < checks.length ? checks[e.key] : false;
            return Material(
              color: checked
                  ? const Color(0xFF34D399).withOpacity(0.08)
                  : cs.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => ref
                    .read(todayHabitChecksProvider.notifier)
                    .toggle(e.key),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: checked
                          ? const Color(0xFF34D399).withOpacity(0.4)
                          : cs.outline,
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(icons[e.key % icons.length],
                          style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          e.value,
                          style: tt.bodySmall?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: cs.onBackground),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IgnorePointer(
                        child: AnimatedCheckbox(
                          checked: checked,
                          color: const Color(0xFF34D399),
                          size: 20,
                          onToggle: () {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
