import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/models/models.dart';
import '../../../core/utils/date_utils.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/progress_bar.dart';
import '../../../shared/widgets/progress_ring.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../../schedule/providers/schedule_provider.dart';
import '../../settings/providers/settings_provider.dart';

const _quotes = [
  '"The secret of getting ahead is getting started." — Mark Twain',
  '"It does not matter how slowly you go as long as you do not stop." — Confucius',
  '"Build something 100 people love." — Paul Graham',
  '"Stay hungry, stay foolish." — Steve Jobs',
  '"First, solve the problem. Then, write the code." — John Johnson',
  '"Code is like humor. When you have to explain it, it is bad." — Cory House',
  '"Programs must be written for people to read." — Harold Abelson',
  '"Simplicity is the soul of efficiency." — Austin Freeman',
  '"Make it work, make it right, make it fast." — Kent Beck',
  '"The best way to predict the future is to invent it." — Alan Kay',
];

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final settingsAsync = ref.watch(settingsProvider);
    final dashAsync = ref.watch(dashboardDataProvider);
    final todayWeekday = DateTime.now().weekday % 7;
    final scheduleAsync = ref.watch(scheduleForWeekdayProvider(todayWeekday));

    final userName = settingsAsync.value?.userName ?? 'there';
    final quote = _quotes[DateTime.now().day % _quotes.length];

    return Scaffold(
      backgroundColor: cs.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(dashboardDataProvider),
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
                      _QuoteCard(quote: quote),
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
                          : _TodayScheduleList(items: items),
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
                    data: (s) => _NonNegotiablesWidget(items: s.nonNegotiables),
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

// ── Quote card ────────────────────────────────────────────

class _QuoteCard extends StatelessWidget {
  final String quote;
  const _QuoteCard({required this.quote});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline),
      ),
      child: Row(
        children: [
          const Text('💬', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              quote,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ),
        ],
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

class _TodayScheduleList extends StatelessWidget {
  final List<ScheduleItem> items;
  const _TodayScheduleList({required this.items});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: items.asMap().entries.map((e) {
          return _ScheduleRow(item: e.value)
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
  const _ScheduleRow({required this.item});

  @override
  ConsumerState<_ScheduleRow> createState() => _ScheduleRowState();
}

class _ScheduleRowState extends ConsumerState<_ScheduleRow> {
  bool _expanded = false;

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
                              widget.item.label,
                              style: tt.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w500),
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
                              Text(goalName!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: accentColor,
                                    fontWeight: FontWeight.w500,
                                  )),
                            ],
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

class _NonNegotiablesWidget extends StatelessWidget {
  final List<String> items;
  const _NonNegotiablesWidget({required this.items});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Daily Non-Negotiables',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Text('🎯', style: const TextStyle(fontSize: 16)),
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
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outline),
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
                          fontWeight: FontWeight.w500, color: cs.onBackground),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
