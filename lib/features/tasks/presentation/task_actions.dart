import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/layout/adaptive_sheet.dart';
import '../../../core/models/today_task.dart';
import '../../../shared/widgets/confirmation_dialog.dart';
import '../../../shared/widgets/item_actions.dart';
import '../../analytics/providers/activity_provider.dart';
import '../../goals/presentation/widgets/create_edit_task_sheet.dart';
import '../data/task_repository.dart';

/// The actions a task offers, shared by every screen that lists tasks
/// outside their goal (Today, the Tasks planner). Same list, same order,
/// same wording everywhere.
class TaskActions {
  const TaskActions._();

  /// Opening a task means opening it for editing — the task is the item.
  static void edit(BuildContext context, TodayTaskContext ctx) {
    final milestoneId = ctx.milestone?.id ?? ctx.task.milestone.value?.id;
    if (milestoneId == null) return;
    final cs = Theme.of(context).colorScheme;
    showAdaptiveSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreateEditTaskSheet(
        milestoneId: milestoneId,
        goalColor: Color(ctx.goal?.colorHex ?? cs.primary.toARGB32()),
        task: ctx.task,
      ),
    );
  }

  static Future<void> delete(
    BuildContext context,
    WidgetRef ref,
    TodayTaskContext ctx,
  ) async {
    final ok = await ConfirmationDialog.show(
      context,
      title: 'Delete Task',
      message: 'Delete "${ctx.task.text}"? This cannot be undone.',
    );
    if (!ok) return;
    await TaskRepository.instance.delete(ctx.task.id);
    if (ref.context.mounted) bumpActivityTick(ref);
  }

  static Future<void> _setDue(
    WidgetRef ref,
    TodayTaskContext ctx,
    DateTime? due,
  ) async {
    await TaskRepository.instance.setDueDate(ctx.task.id, due);
    if (ref.context.mounted) bumpActivityTick(ref);
  }

  static Future<void> toggle(WidgetRef ref, TodayTaskContext ctx) async {
    await TaskRepository.instance.toggleComplete(ctx.task.id);
    if (ref.context.mounted) bumpActivityTick(ref);
  }

  static Future<void> _pickDate(
    BuildContext context,
    WidgetRef ref,
    TodayTaskContext ctx,
  ) async {
    final now = DateTime.now();
    final initial = ctx.dueDate ?? now;
    var first = DateTime(now.year - 1, now.month, now.day);
    if (initial.isBefore(first)) first = initial;
    var last = DateTime(now.year + 10, now.month, now.day);
    if (initial.isAfter(last)) last = initial;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) await _setDue(ref, ctx, picked);
  }

  static List<ItemAction> forTask(
    BuildContext context,
    WidgetRef ref,
    TodayTaskContext ctx,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final task = ctx.task;
    final goalId = ctx.goal?.id;

    return [
      ItemAction(
        label: 'Edit',
        icon: Icons.edit_outlined,
        onSelected: () => edit(context, ctx),
      ),
      ItemAction(
        label: task.isCompleted ? 'Mark as not done' : 'Mark as done',
        icon: task.isCompleted
            ? Icons.radio_button_unchecked_rounded
            : Icons.check_circle_outline_rounded,
        onSelected: () => toggle(ref, ctx),
      ),
      if (!ctx.isDueToday)
        ItemAction(
          label: 'Move to today',
          icon: Icons.wb_sunny_outlined,
          onSelected: () => _setDue(ref, ctx, today),
        ),
      ItemAction(
        label: 'Postpone to tomorrow',
        icon: Icons.next_plan_outlined,
        onSelected: () => _setDue(ref, ctx, tomorrow),
      ),
      ItemAction(
        label: 'Change due date…',
        icon: Icons.edit_calendar_rounded,
        onSelected: () => _pickDate(context, ref, ctx),
      ),
      if (task.dueDate != null)
        ItemAction(
          label: ctx.isDueToday ? 'Remove from today' : 'Clear due date',
          icon: Icons.event_busy_outlined,
          onSelected: () => _setDue(ref, ctx, null),
        ),
      if (goalId != null)
        ItemAction(
          label: 'Open goal',
          icon: Icons.flag_outlined,
          onSelected: () => context.push('/goals/$goalId'),
        ),
      ItemAction(
        label: 'Delete',
        icon: Icons.delete_outline,
        destructive: true,
        onSelected: () => delete(context, ref, ctx),
      ),
    ];
  }

  static void showMenu(
    BuildContext context,
    WidgetRef ref,
    TodayTaskContext ctx,
  ) =>
      showItemActions(
        context,
        title: ctx.task.text,
        actions: forTask(context, ref, ctx),
      );
}
