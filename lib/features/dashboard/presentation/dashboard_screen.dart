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
import '../../../shared/widgets/progress_bar.dart';
import '../../../shared/widgets/progress_ring.dart';
import '../../ai_coach/presentation/daily_briefing_card.dart';
import '../../ai_coach/providers/ai_coach_provider.dart';
import '../../analytics/providers/activity_provider.dart';
import '../../ai_goal/presentation/ai_goal_sheet.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../../schedule/providers/schedule_provider.dart';
import '../../settings/providers/habit_checkin_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../tasks/data/task_repository.dart';
import '../../tasks/providers/task_provider.dart';

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
    return Scaffold(
      backgroundColor: cs.background,
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
              // ── Greeting ───────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${AppDateUtils.greeting()}, $userName 👋',
                        style: tt.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppDateUtils.formatDateWithDay(DateTime.now()),
                        style:
                            tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      const DailyBriefingCard(),
                      const SizedBox(height: 10),
                      _AiQuickAction(
                        onPressed: () async {
                          final goalId = await showAiGoalSheet(context);
                          if (!context.mounted || goalId == null) return;

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('🎉 Goal created! Start working on it.'),
                            ),
                          );
                          context.go('/goals/$goalId');
                        },
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.05),
              ),

              // ── Overall progress ───────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: dashAsync.when(
                    loading: () => const _ProgressCardSkeleton(),
                    error: (e, _) => Text('Error: $e'),
                    data: (data) => _OverallProgressCard(data: data),
                  ),
                ).animate().fadeIn(delay: 100.ms),
              ),

              // ── Goals row ──────────────────────────────────
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                      child: Text('Goals',
                          style: tt.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    dashAsync.when(
                      loading: () => const SizedBox(height: 120),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (data) => data.goals.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 20),
                              child: EmptyState(
                                emoji: '🎯',
                                title: 'No goals yet',
                                subtitle:
                                    'Tap Goals tab to create your first goal.',
                              ),
                            )
                          : _GoalsSummaryRow(data: data),
                    ),
                  ],
                ).animate().fadeIn(delay: 150.ms),
              ),

              // ── Today tasks chip ───────────────────────────
              SliverToBoxAdapter(
                child: _TodayTasksChip(groupedAsync: todayGroupedAsync),
              ),

              // ── Today's tasks preview ──────────────────────
              SliverToBoxAdapter(
                child: _TodayTasksPreview(groupedAsync: todayGroupedAsync),
              ),

              // ── Today's schedule ───────────────────────────
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text("Today's Schedule",
                                style: tt.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                          ),
                          TextButton(
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
                ).animate().fadeIn(delay: 200.ms),
              ),

              // ── Non-negotiables ────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                  child: settingsAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (s) => _NonNegotiablesWidget(
                      items: s.nonNegotiables,
                      checks: habitsAsync.valueOrNull ?? List.filled(4, false),
                      streak: streakAsync.valueOrNull ?? 0,
                    ),
                  ),
                ).animate().fadeIn(delay: 250.ms),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiQuickAction extends StatelessWidget {
  const _AiQuickAction({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ActionChip(
        avatar: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF5B9CF6), Color(0xFFA78BFA)],
          ).createShader(bounds),
          child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
        ),
        label: const Text('✦ Generate with AI'),
        onPressed: onPressed,
      ),
    );
  }
}

class _TodayTasksChip extends StatelessWidget {
  final AsyncValue<TodayTasksData> groupedAsync;
  const _TodayTasksChip({required this.groupedAsync});

  @override
  Widget build(BuildContext context) {
    return groupedAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (data) {
        final count = data.actionableCount;
        if (count == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: ActionChip(
            avatar: const Icon(Icons.today, size: 18),
            label: Text('$count task${count == 1 ? '' : 's'} due — open Today'),
            onPressed: () => context.go('/today'),
          ),
        );
      },
    );
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

class _OverallProgressCard extends StatelessWidget {
  final DashboardData data;
  const _OverallProgressCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF5B9CF6).withOpacity(0.15),
            const Color(0xFF34D399).withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outline),
      ),
      child: Row(
        children: [
          ProgressRing(
            percent: data.overallPercent,
            color: const Color(0xFF5B9CF6),
            size: 80,
            strokeWidth: 7,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(data.overallPercent * 100).toInt()}%',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF5B9CF6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Overall Progress',
                    style:
                        tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  '${data.totalDone} of ${data.totalTasks} tasks completed',
                  style: tt.bodySmall,
                ),
                const SizedBox(height: 10),
                ProgressBar(
                  percent: data.overallPercent,
                  color: const Color(0xFF5B9CF6),
                  height: 6,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressCardSkeleton extends StatelessWidget {
  const _ProgressCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }
}

// ── Goals summary row ─────────────────────────────────────

class _GoalsSummaryRow extends ConsumerWidget {
  final DashboardData data;
  const _GoalsSummaryRow({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 130,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: data.goals.length,
        itemBuilder: (context, i) {
          final goal = data.goals[i];
          final color = Color(goal.colorHex);
          final pct = data.goalProgress[goal.id] ?? 0;
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () => context.push('/goals/${goal.id}'),
              child: Container(
                width: 120,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(goal.emoji, style: const TextStyle(fontSize: 22)),
                        const Spacer(),
                        ProgressRing(
                          percent: pct,
                          color: color,
                          size: 32,
                          strokeWidth: 3,
                          child: Text(
                            '${(pct * 100).toInt()}%',
                            style: TextStyle(
                              fontSize: 7,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      goal.name,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onBackground,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ).animate().fadeIn(delay: (i * 40).ms).slideX(begin: 0.1);
        },
      ),
    );
  }
}

// ── Today's schedule list ─────────────────────────────────

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
