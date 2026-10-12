import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/models/habit_icons.dart';
import '../../../../core/models/models.dart';
import '../../../../core/services/habit_customization_service.dart';
import '../../../analytics/providers/activity_provider.dart';
import '../../../habits/data/habit_repository.dart';
import '../../../habits/presentation/widgets/habit_calendar_row.dart';
import '../../../habits/presentation/widgets/habit_edit_sheet.dart';
import '../../../habits/providers/habit_provider.dart';

/// A focused, modern daily habit tracker section for the dashboard.
///
/// Features:
/// - Horizontal calendar row for current days (select any date!)
/// - Dedicated habit cards with custom colors, icons, repeat tags, and reminders
/// - Tactile one-tap checkoff for the selected date
/// - Quick habit creation and customization
class DailyHabitsSection extends ConsumerStatefulWidget {
  const DailyHabitsSection({
    super.key,
    required this.habits,
    required this.checked,
    required this.streak,
  });

  final List<Habit> habits;
  final Set<String> checked;
  final int streak;

  @override
  ConsumerState<DailyHabitsSection> createState() => _DailyHabitsSectionState();
}

class _DailyHabitsSectionState extends ConsumerState<DailyHabitsSection> {
  DateTime _selectedDate = DateTime.now();

  DateTime get _normalizedDate =>
      DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);

  bool get _isViewingToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  Future<void> _toggle(String habitUid, Set<String> currentChecked) async {
    HapticFeedback.lightImpact();
    final targetDate = _normalizedDate;
    final isChecked = currentChecked.contains(habitUid);
    final service = ref.read(habitCheckinServiceProvider);

    await service.setChecked(targetDate, habitUid, !isChecked);
    ref.read(habitActivityTickProvider.notifier).state++;
    ref.read(activityTickProvider.notifier).state++;
    ref.invalidate(todayHabitChecksProvider);
    ref.invalidate(habitChecksForDateProvider(targetDate));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    ref.watch(habitCustomizationVersionProvider);

    // If viewing today, use widget.checked; otherwise read for selected date
    final effectiveChecked = _isViewingToday
        ? widget.checked
        : (ref.watch(habitChecksForDateProvider(_normalizedDate)).valueOrNull ??
            const <String>{});

    final now = DateTime.now();
    final startOfWeek =
        _normalizedDate.subtract(Duration(days: _normalizedDate.weekday - 1));
    final completedDays = ref
            .watch(habitCompletedDaysInWeekProvider(startOfWeek))
            .valueOrNull ??
        const <String>{};

    final total = widget.habits.length;
    final done = widget.habits
        .where((h) => effectiveChecked.contains(h.uid))
        .length;
    final percent = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
    final allCompleted = total > 0 && done == total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section Header ───────────────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Row(
                children: [
                  Text(
                    'Daily habits',
                    style: tt.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                  if (total > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: allCompleted
                            ? const Color(0xFF10B981).withValues(alpha: 0.16)
                            : cs.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$done/$total done',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: allCompleted
                              ? const Color(0xFF10B981)
                              : cs.primary,
                        ),
                      ),
                    ),
                  ],
                  if (widget.streak > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('🔥 ', style: TextStyle(fontSize: 11)),
                          Text(
                            '${widget.streak} ${widget.streak == 1 ? 'day' : 'days'}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFF59E0B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'New habit',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.add_rounded, size: 20, color: cs.primary),
              onPressed: () => HabitEditSheet.show(context),
            ),
            IconButton(
              tooltip: 'Open Habit Tracker',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.arrow_forward_rounded,
                  size: 18, color: cs.onSurfaceVariant),
              onPressed: () => context.go('/habits'),
            ),
          ],
        ),

        // ── Calendar Week Row of Current Days ─────────────────────
        const SizedBox(height: 4),
        HabitCalendarRow(
          selectedDate: _selectedDate,
          onDateSelected: (date) {
            setState(() => _selectedDate = date);
          },
          completedDates: completedDays,
        ),
        const SizedBox(height: 10),

        // ── Progress Bar ──────────────────────────────────────────
        if (total > 0) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 4,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                allCompleted ? const Color(0xFF10B981) : cs.primary,
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],

        // ── Habits Content ────────────────────────────────────────
        if (widget.habits.isEmpty)
          _EmptyHabitsCard(onAdd: () => HabitEditSheet.show(context))
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final isTwoCol = constraints.maxWidth >= 340;
              final colCount = isTwoCol ? 2 : 1;

              return GridView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: colCount,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: isTwoCol ? 2.3 : 3.8,
                ),
                itemCount: widget.habits.length,
                itemBuilder: (context, index) {
                  final habit = widget.habits[index];
                  final isDone = effectiveChecked.contains(habit.uid);
                  return _HabitCard(
                    habit: habit,
                    isDone: isDone,
                    onToggle: () => _toggle(habit.uid, effectiveChecked),
                    onEdit: () => HabitEditSheet.show(context, habit: habit),
                  );
                },
              );
            },
          ),
      ],
    );
  }
}

/// A tactile habit card with custom accent color, icon, and repeat rules.
class _HabitCard extends ConsumerWidget {
  const _HabitCard({
    required this.habit,
    required this.isDone,
    required this.onToggle,
    required this.onEdit,
  });

  final Habit habit;
  final bool isDone;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final customAsync = ref.watch(habitCustomizationProvider(habit.uid));
    final custom = customAsync.valueOrNull ?? const HabitCustomization();
    final habitColor = custom.color;

    final habitTitle =
        habit.label.trim().isEmpty ? 'Unnamed habit' : habit.label.trim();
    final iconData = HabitIcons.resolve(habit.iconKey);

    return Material(
      color: isDone
          ? habitColor.withValues(alpha: 0.08)
          : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onToggle,
        onLongPress: onEdit,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDone
                  ? habitColor.withValues(alpha: 0.45)
                  : cs.outline.withValues(alpha: 0.7),
              width: isDone ? 1.4 : 1.0,
            ),
          ),
          child: Row(
            children: [
              // ── Dedicated Habit Icon Badge (Tap icon to edit) ────
              GestureDetector(
                onTap: onEdit,
                child: Tooltip(
                  message: 'Edit habit',
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isDone
                          ? habitColor
                          : habitColor.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                      boxShadow: isDone
                          ? [
                              BoxShadow(
                                color: habitColor.withValues(alpha: 0.25),
                                blurRadius: 8,
                                spreadRadius: 1,
                              )
                            ]
                          : null,
                    ),
                    child: Icon(
                      iconData,
                      size: 20,
                      color: isDone ? Colors.white : habitColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // ── Habit Name and Label ──────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      habitTitle,
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isDone
                            ? cs.onSurface.withValues(alpha: 0.7)
                            : cs.onSurface,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          custom.repeatSummary,
                          style: tt.labelSmall?.copyWith(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        if (custom.hasReminder) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.notifications_active_rounded,
                              size: 10, color: habitColor),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),

              // ── Interactive Check Button ──────────────────────────
              GestureDetector(
                onTap: onToggle,
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDone ? habitColor : Colors.transparent,
                    border: Border.all(
                      color: isDone ? habitColor : cs.outline,
                      width: isDone ? 0 : 2,
                    ),
                  ),
                  child: isDone
                      ? const Icon(
                          Icons.check_rounded,
                          size: 17,
                          color: Colors.white,
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inviting empty state for users who haven't added habits yet.
class _EmptyHabitsCard extends StatelessWidget {
  const _EmptyHabitsCard({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onAdd,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outline),
          color: cs.surfaceContainerHighest,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.add_task_rounded, color: cs.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Track daily habits',
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Add habits with custom colors, repeat schedules and alerts',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
