import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/models/models.dart';
import '../../../../core/services/habit_customization_service.dart';
import '../../../analytics/providers/activity_provider.dart';
import '../../../habits/presentation/widgets/habit_edit_sheet.dart';
import '../../../habits/presentation/widgets/habit_row.dart';
import '../../../habits/providers/habit_provider.dart';

/// Today's habits on the Today tab: tick them off, nothing else.
///
/// The week calendar, past-day editing and habit management all live on the
/// Habits tab. Repeating them here made the home page look like a second
/// habit tracker, so this section shows only the habits due today and a link
/// across.
class DailyHabitsSection extends ConsumerWidget {
  const DailyHabitsSection({
    super.key,
    required this.habits,
    required this.checked,
    required this.streak,
  });

  final List<Habit> habits;
  final Set<String> checked;

  /// Kept for callers; the streak is shown once, in the summary at the top.
  final int streak;

  Future<void> _toggle(WidgetRef ref, String habitUid) async {
    HapticFeedback.lightImpact();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final service = ref.read(habitCheckinServiceProvider);

    await service.setChecked(today, habitUid, !checked.contains(habitUid));
    ref.read(habitActivityTickProvider.notifier).state++;
    ref.read(activityTickProvider.notifier).state++;
    ref.invalidate(todayHabitChecksProvider);
    ref.invalidate(habitChecksForDateProvider(today));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    ref.watch(habitCustomizationVersionProvider);

    // Only habits scheduled for today's weekday belong on the Today tab.
    final weekday = DateTime.now().weekday;
    final dueToday = habits.where((h) {
      final custom = ref.watch(habitCustomizationProvider(h.uid)).valueOrNull ??
          const HabitCustomization();
      return custom.isScheduledForWeekday(weekday);
    }).toList();
    final total = dueToday.length;
    final done = dueToday.where((h) => checked.contains(h.uid)).length;
    final allCompleted = total > 0 && done == total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Habits',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (total > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: allCompleted
                      ? const Color(0xFF10B981).withValues(alpha: 0.16)
                      : cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  allCompleted ? 'All done' : '$done/$total done',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: allCompleted ? const Color(0xFF10B981) : cs.primary,
                  ),
                ),
              ),
            ],
            const Spacer(),
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: () => context.go('/habits'),
              child: const Text('See all'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (habits.isEmpty)
          _EmptyHabitsCard(onAdd: () => HabitEditSheet.show(context))
        else if (dueToday.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Text(
              'No habits scheduled for today.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          )
        else
          // The same row as the Habits tab, so a habit behaves identically
          // wherever it appears.
          Column(
            children: [
              for (final habit in dueToday) ...[
                HabitRow(
                  habit: habit,
                  isDone: checked.contains(habit.uid),
                  onToggle: () => _toggle(ref, habit.uid),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
      ],
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
