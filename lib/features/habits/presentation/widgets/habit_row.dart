import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/models/habit_icons.dart';
import '../../../../core/models/models.dart';
import '../../../../core/services/habit_customization_service.dart';
import '../../../../shared/widgets/animated_checkbox.dart';
import '../../../../shared/widgets/confirmation_dialog.dart';
import '../../../../shared/widgets/item_actions.dart';
import '../../data/habit_repository.dart';
import 'habit_edit_sheet.dart';
import 'habit_month_calendar.dart';

/// One habit, the same on the Habits tab and on Today.
///
/// Follows the app-wide item rule: tap ticks it, long-press opens the options
/// (Edit, History, Mark done, Delete), swipe left for Edit/Delete. Habit rows
/// carry no ⋯ button; the checkbox already sits at the end of the row.
class HabitRow extends ConsumerWidget {
  const HabitRow({
    super.key,
    required this.habit,
    required this.isDone,
    required this.onToggle,
  });

  final Habit habit;
  final bool isDone;
  final VoidCallback onToggle;

  List<ItemAction> _actions(BuildContext context, WidgetRef ref) =>
      habitActions(context, ref, habit, isDone: isDone, onToggle: onToggle);

  Future<void> _delete(BuildContext context, WidgetRef ref) =>
      deleteHabit(context, ref, habit);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final custom =
        ref.watch(habitCustomizationProvider(habit.uid)).valueOrNull ??
            const HabitCustomization();

    final habitColor = custom.color;

    return ItemSwipeActions(
      itemKey: ValueKey('habit-${habit.uid}'),
      onEdit: () => HabitEditSheet.show(context, habit: habit),
      onDelete: () => _delete(context, ref),
      child: Material(
        color: isDone
            ? habitColor.withValues(alpha: 0.08)
            : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onToggle,
          onLongPress: () => showItemActions(context,
              title: habit.label, actions: _actions(context, ref)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDone
                    ? habitColor.withValues(alpha: 0.45)
                    : cs.outline.withValues(alpha: 0.7),
                width: isDone ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isDone
                        ? habitColor
                        : habitColor.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    HabitIcons.resolve(habit.iconKey),
                    size: 20,
                    color: isDone ? Colors.white : habitColor,
                  ),
                ),
                const SizedBox(width: 12),

                // Title and Tags
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        habit.label.isEmpty ? 'Unnamed habit' : habit.label,
                        style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isDone
                              ? cs.onSurface.withValues(alpha: 0.6)
                              : cs.onSurface,
                          decoration:
                              isDone ? TextDecoration.lineThrough : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            custom.repeatSummary,
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                          if (custom.hasReminder) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: habitColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.notifications_active_rounded,
                                      size: 10, color: habitColor),
                                  const SizedBox(width: 3),
                                  Text(
                                    custom.reminderFormatted,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: habitColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Interactive Checkbox
                AnimatedCheckbox(
                  checked: isDone,
                  color: habitColor,
                  size: 22,
                  onToggle: onToggle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> deleteHabit(
    BuildContext context, WidgetRef ref, Habit habit) async {
  final ok = await ConfirmationDialog.show(
    context,
    title: 'Remove Habit?',
    message: 'Remove "${habit.label}" from your habits?',
    confirmLabel: 'Remove',
  );
  if (!ok) return;
  await HabitRepository.instance.delete(habit.id);
  await HabitCustomizationService.instance.delete(habit.uid);
  ref.read(habitCustomizationVersionProvider.notifier).state++;
}

/// A habit's options, in the same order wherever a habit is listed. The
/// mark-done entry is shown only where there is a day to mark it for.
List<ItemAction> habitActions(
  BuildContext context,
  WidgetRef ref,
  Habit habit, {
  bool? isDone,
  VoidCallback? onToggle,
}) =>
    [
      ItemAction(
        label: 'Edit',
        icon: Icons.edit_outlined,
        onSelected: () => HabitEditSheet.show(context, habit: habit),
      ),
      ItemAction(
        label: 'History',
        icon: Icons.calendar_month_rounded,
        onSelected: () => HabitHistorySheet.show(context, habit),
      ),
      if (isDone != null && onToggle != null)
        ItemAction(
          label: isDone ? 'Mark as not done' : 'Mark as done',
          icon: isDone
              ? Icons.radio_button_unchecked_rounded
              : Icons.check_circle_outline_rounded,
          onSelected: onToggle,
        ),
      ItemAction(
        label: 'Delete',
        icon: Icons.delete_outline,
        destructive: true,
        onSelected: () => deleteHabit(context, ref, habit),
      ),
    ];
