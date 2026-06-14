import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/widgets/progress_ring.dart';
import '../../ai_coach/presentation/ai_weekly_review_section.dart';
import '../providers/activity_provider.dart';
import '../providers/analytics_provider.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final dataAsync = ref.watch(analyticsDataProvider);

    return Scaffold(
      backgroundColor: cs.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(analyticsDataProvider);
            bumpActivityTick(ref);
          },
          child: dataAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (data) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
              children: [
                Text(
                  'Stats',
                  style: tt.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ).animate().fadeIn(),

                const SizedBox(height: 20),

                AiWeeklyReviewSection(data: data)
                    .animate()
                    .fadeIn(delay: 60.ms)
                    .slideY(begin: 0.05),

                const SizedBox(height: 20),

                _WeekSummaryCard(data: data)
                    .animate()
                    .fadeIn(delay: 80.ms)
                    .slideY(begin: 0.05),

                const SizedBox(height: 20),

                _BarChartCard(data: data)
                    .animate()
                    .fadeIn(delay: 120.ms)
                    .slideY(begin: 0.05),

                const SizedBox(height: 20),

                if (data.goalStats.isNotEmpty) ...[
                  Text(
                    'Goals Breakdown',
                    style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ).animate().fadeIn(delay: 160.ms),
                  const SizedBox(height: 12),
                  ...data.goalStats.asMap().entries.map(
                        (e) => _GoalStatRow(
                          stat: e.value,
                          onTap: () =>
                              context.push('/goals/${e.value.goal.id}'),
                        ).animate().fadeIn(delay: (160 + e.key * 40).ms),
                      ),
                  const SizedBox(height: 20),
                ],

                _MonthlyHeatmap(data: data)
                    .animate()
                    .fadeIn(delay: 240.ms)
                    .slideY(begin: 0.05),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Week summary card ─────────────────────────────────────

class _WeekSummaryCard extends StatelessWidget {
  final AnalyticsData data;
  const _WeekSummaryCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final pct = data.weekChangePercent;
    final up = pct >= 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary.withOpacity(0.10),
            cs.surfaceContainerHighest,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This Week',
            style: tt.titleSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${data.thisWeekDone}',
                style: tt.displaySmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'activities',
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              const Spacer(),
              if (data.lastWeekDone > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: up
                        ? const Color(0xFF34D399).withOpacity(0.15)
                        : const Color(0xFFF87171).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        up
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded,
                        size: 16,
                        color: up
                            ? const Color(0xFF34D399)
                            : const Color(0xFFF87171),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${(pct * 100).abs().toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: up
                              ? const Color(0xFF34D399)
                              : const Color(0xFFF87171),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _StatChip(label: '🔥 Streak', value: '${data.currentStreak}d'),
              const SizedBox(width: 10),
              _StatChip(label: '🏆 Best', value: '${data.longestStreak}d'),
              const SizedBox(width: 10),
              _StatChip(label: '⭐ Best Day', value: data.bestDay),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outline),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── 7-day bar chart ───────────────────────────────────────

class _BarChartCard extends StatelessWidget {
  final AnalyticsData data;
  const _BarChartCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final maxVal = data.last7Days.isEmpty
        ? 0
        : data.last7Days.reduce((a, b) => a > b ? a : b);
    final max = maxVal.toDouble();

    final now = DateTime.now();
    const dayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final labels = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return dayLabels[d.weekday % 7];
    });

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Last 7 Days',
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 150,
            child: BarChart(
              BarChartData(
                maxY: max == 0 ? 5 : max + 1,
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, _) => Text(
                        labels[v.toInt()],
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: cs.outline.withOpacity(0.3),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(
                  7,
                  (i) => BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: data.last7Days[i].toDouble(),
                        color: i == 6
                            ? cs.primary
                            : cs.primary.withOpacity(0.4),
                        width: 20,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Goal stat row ─────────────────────────────────────────

class _GoalStatRow extends StatelessWidget {
  final GoalStat stat;
  final VoidCallback onTap;

  const _GoalStatRow({required this.stat, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = Color(stat.goal.colorHex);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: cs.outline),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                ProgressRing(
                  percent: stat.percent,
                  color: color,
                  size: 44,
                  strokeWidth: 4,
                  child: Text(
                    '${(stat.percent * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(stat.goal.emoji),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              stat.goal.name,
                              style: tt.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${stat.done}/${stat.total} tasks',
                        style: tt.bodySmall,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Monthly heatmap ───────────────────────────────────────

class _MonthlyHeatmap extends StatelessWidget {
  final AnalyticsData data;
  const _MonthlyHeatmap({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final maxVal = data.monthlyHeatmap.values.isEmpty
        ? 1
        : data.monthlyHeatmap.values.reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Activity',
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Text(
                '${_monthName(now.month)} ${now.year}',
                style: tt.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: List.generate(daysInMonth, (i) {
              final day = i + 1;
              final count = data.monthlyHeatmap[day] ?? 0;
              final intensity = maxVal == 0 ? 0.0 : count / maxVal;
              final isToday = day == now.day;

              return Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: count == 0
                      ? cs.surface
                      : cs.primary.withOpacity(0.15 + 0.7 * intensity),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isToday ? cs.primary : cs.outline.withOpacity(0.5),
                    width: isToday ? 2 : 1,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                    color: count > 0 ? cs.primary : cs.onSurfaceVariant,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  String _monthName(int m) {
    const names = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return names[m];
  }
}
