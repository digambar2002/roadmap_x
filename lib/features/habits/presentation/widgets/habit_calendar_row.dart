import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// An interactive horizontal calendar row showing the current week of days.
///
/// Features:
/// - Weekday names and day numbers
/// - Selected day indicator (filled circle / pill)
/// - Day completion indicator dot
/// - Previous/Next week navigation and "Today" jump button
class HabitCalendarRow extends StatelessWidget {
  const HabitCalendarRow({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
    this.completedDates = const {},
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final Set<String> completedDates;

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Compute the 7 days of the week containing selectedDate
    // Monday as start of week (weekday 1)
    final startOfWeek = selectedDate.subtract(Duration(days: selectedDate.weekday - 1));
    final weekDays = List.generate(7, (i) {
      return DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day + i);
    });

    final isViewingToday = _isSameDay(selectedDate, today);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Navigation Bar ──────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              Text(
                DateFormat('MMMM yyyy').format(selectedDate),
                style: tt.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              if (!isViewingToday) ...[
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    onDateSelected(today);
                  },
                  child: const Text('Today'),
                ),
                const SizedBox(width: 4),
              ],
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  onDateSelected(selectedDate.subtract(const Duration(days: 7)));
                },
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  onDateSelected(selectedDate.add(const Duration(days: 7)));
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),

        // ── 7-Day Horizontal Strip ──────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: weekDays.map((day) {
            final isSelected = _isSameDay(day, selectedDate);
            final isToday = _isSameDay(day, today);
            final dayKey = _dayKey(day);
            final isComplete = completedDates.contains(dayKey);

            return Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onDateSelected(day);
                },
                child: _CalendarDayItem(
                  day: day,
                  isSelected: isSelected,
                  isToday: isToday,
                  isComplete: isComplete,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _CalendarDayItem extends StatelessWidget {
  const _CalendarDayItem({
    required this.day,
    required this.isSelected,
    required this.isToday,
    required this.isComplete,
  });

  final DateTime day;
  final bool isSelected;
  final bool isToday;
  final bool isComplete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final weekdayName = DateFormat('E').format(day); // Mon, Tue...
    final dayNumber = day.day.toString();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? cs.primary
            : (isToday
                ? cs.primary.withValues(alpha: 0.12)
                : cs.surfaceContainerHighest.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? cs.primary
              : (isToday ? cs.primary.withValues(alpha: 0.4) : cs.outline.withValues(alpha: 0.6)),
          width: isSelected || isToday ? 1.5 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Weekday abbreviation
          Text(
            weekdayName,
            style: tt.labelSmall?.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isSelected
                  ? Colors.white.withValues(alpha: 0.85)
                  : cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),

          // Day of month number
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected ? Colors.white : Colors.transparent,
            ),
            child: Text(
              dayNumber,
              style: tt.titleSmall?.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isSelected
                    ? cs.primary
                    : (isToday ? cs.primary : cs.onSurface),
              ),
            ),
          ),
          const SizedBox(height: 4),

          // Completion status dot
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isComplete
                  ? (isSelected ? Colors.white : const Color(0xFF10B981))
                  : Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }
}
