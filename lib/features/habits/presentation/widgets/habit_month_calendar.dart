import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/layout/adaptive_sheet.dart';
import '../../../../core/models/habit_icons.dart';
import '../../../../core/models/models.dart';
import '../../../../core/services/habit_customization_service.dart';
import '../../providers/habit_provider.dart';

/// Stats for one habit, derived from the days it was ticked.
class HabitStats {
  const HabitStats({
    required this.thisMonth,
    required this.currentStreak,
    required this.bestStreak,
    required this.total,
  });

  final int thisMonth;
  final int currentStreak;
  final int bestStreak;
  final int total;

  /// Streaks only count days the habit is scheduled for, so a weekdays-only
  /// habit is not broken by the weekend. An unticked today does not break the
  /// current streak, because the day is not over yet.
  static HabitStats from(
    Set<DateTime> done,
    HabitCustomization custom, {
    DateTime? now,
  }) {
    final today = _day(now ?? DateTime.now());

    final thisMonth = done
        .where((d) => d.year == today.year && d.month == today.month)
        .length;

    var current = 0;
    for (var i = 0; i < 3650; i++) {
      final day = DateTime(today.year, today.month, today.day - i);
      if (!custom.isScheduledForWeekday(day.weekday)) continue;
      if (done.contains(day)) {
        current++;
      } else if (i == 0) {
        continue;
      } else {
        break;
      }
    }

    var best = 0;
    if (done.isNotEmpty) {
      final sorted = done.toList()..sort();
      var run = 0;
      DateTime? previous;
      for (final day in sorted) {
        if (previous != null && _nextScheduled(previous, custom) == day) {
          run++;
        } else {
          run = 1;
        }
        if (run > best) best = run;
        previous = day;
      }
    }

    return HabitStats(
      thisMonth: thisMonth,
      currentStreak: current,
      bestStreak: best,
      total: done.length,
    );
  }

  static DateTime _nextScheduled(DateTime from, HabitCustomization custom) {
    var d = DateTime(from.year, from.month, from.day + 1);
    for (var i = 0; i < 7; i++) {
      if (custom.isScheduledForWeekday(d.weekday)) return d;
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return d;
  }
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Full history for one habit: stats, then a month calendar that can be
/// paged by month and by year, with every completed day filled in.
class HabitHistorySheet extends ConsumerStatefulWidget {
  const HabitHistorySheet({super.key, required this.habit});

  final Habit habit;

  static Future<void> show(BuildContext context, Habit habit) {
    return showAdaptiveSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => HabitHistorySheet(habit: habit),
    );
  }

  @override
  ConsumerState<HabitHistorySheet> createState() => _HabitHistorySheetState();
}

class _HabitHistorySheetState extends ConsumerState<HabitHistorySheet> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  DateTime get _currentMonth =>
      DateTime(DateTime.now().year, DateTime.now().month);

  /// Months and years page freely in both directions. Days before the habit
  /// existed and days still to come are drawn faded rather than blocked, so
  /// the arrows always do something.
  void _shift({int months = 0, int years = 0}) {
    setState(() {
      _month = DateTime(_month.year + years, _month.month + months);
    });
  }

  void _jumpToCurrent() => setState(() => _month = _currentMonth);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final habit = widget.habit;
    final custom =
        ref.watch(habitCustomizationProvider(habit.uid)).valueOrNull ??
            const HabitCustomization();
    final done = ref.watch(habitCheckedDatesProvider(habit.uid)).valueOrNull ??
        const <DateTime>{};
    final stats = HabitStats.from(done, custom);
    final color = custom.color;

    final isCurrentMonth = _month == _currentMonth;

    final monthDone = done
        .where((d) => d.year == _month.year && d.month == _month.month)
        .length;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(HabitIcons.resolve(habit.iconKey), color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        habit.label.isEmpty ? 'Unnamed habit' : habit.label,
                        style: tt.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${custom.category} · ${custom.repeatSummary}',
                        style:
                            tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _Stat(value: '${stats.currentStreak}', label: 'Streak'),
                _Stat(value: '${stats.bestStreak}', label: 'Best'),
                _Stat(value: '${stats.thisMonth}', label: 'This month'),
                _Stat(value: '${stats.total}', label: 'Total'),
              ],
            ),
            const SizedBox(height: 16),
            // ── Month / year navigation ───────────────────────
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous year',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _shift(years: -1),
                  icon: const Icon(Icons.keyboard_double_arrow_left_rounded),
                ),
                IconButton(
                  tooltip: 'Previous month',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _shift(months: -1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        DateFormat('MMMM yyyy').format(_month),
                        textAlign: TextAlign.center,
                        style: tt.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (isCurrentMonth)
                        Text(
                          '$monthDone day${monthDone == 1 ? '' : 's'} done',
                          style: tt.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        )
                      else
                        GestureDetector(
                          onTap: _jumpToCurrent,
                          child: Text(
                            '$monthDone day${monthDone == 1 ? '' : 's'} done'
                            ' · Back to this month',
                            style: tt.labelSmall?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _shift(months: 1),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
                IconButton(
                  tooltip: 'Next year',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _shift(years: 1),
                  icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GestureDetector(
              // Swipe left/right to change month.
              onHorizontalDragEnd: (details) {
                final v = details.primaryVelocity ?? 0;
                if (v < -200) _shift(months: 1);
                if (v > 200) _shift(months: -1);
              },
              child: HabitMonthGrid(
                month: _month,
                done: done,
                color: color,
                isScheduled: custom.isScheduledForWeekday,
                createdAt: habit.createdAt,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Legend(color: color, label: 'Done'),
                const SizedBox(width: 16),
                _Legend(
                  color: Colors.transparent,
                  border: cs.primary,
                  label: 'Today',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A Monday-first month grid with completed days filled in [color].
class HabitMonthGrid extends StatelessWidget {
  const HabitMonthGrid({
    super.key,
    required this.month,
    required this.done,
    required this.color,
    required this.isScheduled,
    required this.createdAt,
  });

  final DateTime month;
  final Set<DateTime> done;
  final Color color;
  final bool Function(int weekday) isScheduled;
  final DateTime createdAt;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final today = _day(DateTime.now());
    final created = _day(createdAt);

    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = DateTime(month.year, month.month, 1).weekday - 1;
    final cells = leading + daysInMonth;
    final rows = (cells / 7).ceil();

    const weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Column(
      children: [
        Row(
          children: [
            for (final w in weekdays)
              Expanded(
                child: Center(
                  child: Text(
                    w,
                    style: tt.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(
                  child: Builder(builder: (context) {
                    final index = r * 7 + c;
                    final dayNum = index - leading + 1;
                    if (dayNum < 1 || dayNum > daysInMonth) {
                      return const SizedBox(height: 42);
                    }
                    final date = DateTime(month.year, month.month, dayNum);
                    final isDone = done.contains(date);
                    final isToday = date == today;
                    final isFuture = date.isAfter(today);
                    final beforeStart = date.isBefore(created) && !isDone;
                    final scheduled = isScheduled(date.weekday);
                    final faded = isFuture || beforeStart || !scheduled;

                    return Padding(
                      padding: const EdgeInsets.all(3),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Container(
                          key: ValueKey('day-$dayNum'),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDone
                                ? color
                                : (faded
                                    ? Colors.transparent
                                    : cs.surfaceContainerHighest),
                            border: isToday
                                ? Border.all(color: cs.primary, width: 2)
                                : null,
                          ),
                          child: Text(
                            '$dayNum',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  isDone || isToday ? FontWeight.w700 : null,
                              color: isDone
                                  ? Colors.white
                                  : cs.onSurface
                                      .withValues(alpha: faded ? 0.35 : 0.85),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
            ],
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            label,
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, this.border});
  final Color color;
  final Color? border;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border:
                border == null ? null : Border.all(color: border!, width: 2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}
