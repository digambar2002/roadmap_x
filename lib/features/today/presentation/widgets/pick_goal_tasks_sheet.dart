import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/layout/adaptive_sheet.dart';
import '../../../../core/models/models.dart';
import '../../../../core/models/today_task.dart';
import '../../../../shared/widgets/bottom_sheet_handle.dart';
import '../../../../shared/widgets/custom_button.dart';
import '../../../../shared/widgets/due_date_badge.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../analytics/providers/activity_provider.dart';
import '../../../goals/providers/goal_provider.dart';
import '../../../milestones/providers/milestone_provider.dart';
import '../../../tasks/data/task_repository.dart';
import '../../../tasks/providers/task_provider.dart';

class PickGoalTasksSheet extends HookConsumerWidget {
  const PickGoalTasksSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final searchCtrl = useTextEditingController();
    final searchQuery = useState('');
    final selectedGoalUid = useState<String?>(null);
    final selectedTaskIds = useState<Set<int>>({});
    final isSaving = useState(false);

    useEffect(() {
      void listener() => searchQuery.value = searchCtrl.text.trim();
      searchCtrl.addListener(listener);
      return () => searchCtrl.removeListener(listener);
    }, [searchCtrl]);

    final activeTasksAsync = ref.watch(activeTaskContextsProvider);
    final activeGoalsAsync = ref.watch(activeGoalsProvider);

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: activeTasksAsync.when(
        loading: () => const SizedBox(
          height: 300,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => SizedBox(
          height: 200,
          child: Center(child: Text('Error loading tasks: $e')),
        ),
        data: (allContexts) {
          // Available tasks to add to today: uncompleted tasks that are not yet due today
          final availableContexts =
              allContexts.where((ctx) => !ctx.isDueToday).toList();

          // Filter by selected goal
          var filtered = availableContexts;
          if (selectedGoalUid.value != null) {
            filtered = filtered
                .where((ctx) => ctx.goal?.uid == selectedGoalUid.value)
                .toList();
          }

          // Filter by search query
          if (searchQuery.value.isNotEmpty) {
            final q = searchQuery.value.toLowerCase();
            filtered = filtered.where((ctx) {
              final taskText = ctx.task.text.toLowerCase();
              final goalName = ctx.goal?.name.toLowerCase() ?? '';
              final milestoneTitle = ctx.milestone?.title.toLowerCase() ?? '';
              return taskText.contains(q) ||
                  goalName.contains(q) ||
                  milestoneTitle.contains(q);
            }).toList();
          }

          Future<void> addToToday() async {
            if (selectedTaskIds.value.isEmpty || isSaving.value) return;
            isSaving.value = true;
            try {
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              await TaskRepository.instance
                  .setDueDates(selectedTaskIds.value.toList(), today);
              bumpActivityTick(ref);
              ref.invalidate(todayTasksGroupedProvider);
              if (context.mounted) {
                Navigator.of(context).maybePop(selectedTaskIds.value.length);
              }
            } finally {
              isSaving.value = false;
            }
          }

          final goals = activeGoalsAsync.valueOrNull ?? [];
          final allFilteredIds = filtered.map((c) => c.task.id).toSet();
          final areAllFilteredSelected = allFilteredIds.isNotEmpty &&
              allFilteredIds.every((id) => selectedTaskIds.value.contains(id));

          return SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const BottomSheetHandle(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pick Tasks for Today',
                              style: tt.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Select tasks from your goals to work on today',
                              style: tt.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),

                // Search Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search tasks or goals…',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: searchQuery.value.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => searchCtrl.clear(),
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // Goal Chips Filter
                if (goals.isNotEmpty)
                  SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        _GoalFilterChip(
                          label: 'All Goals',
                          count: availableContexts.length,
                          isSelected: selectedGoalUid.value == null,
                          onTap: () => selectedGoalUid.value = null,
                        ),
                        for (final goal in goals) ...[
                          const SizedBox(width: 8),
                          _GoalFilterChip(
                            emoji: goal.emoji,
                            label: goal.name,
                            color: Color(goal.colorHex),
                            count: availableContexts
                                .where((c) => c.goal?.uid == goal.uid)
                                .length,
                            isSelected: selectedGoalUid.value == goal.uid,
                            onTap: () => selectedGoalUid.value = goal.uid,
                          ),
                        ],
                      ],
                    ),
                  ),

                const SizedBox(height: 8),

                // Selection Header (Select All & Quick Add)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Row(
                    children: [
                      Text(
                        '${filtered.length} task${filtered.length == 1 ? '' : 's'} available',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (filtered.isNotEmpty)
                        TextButton(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () {
                            final next = Set<int>.from(selectedTaskIds.value);
                            if (areAllFilteredSelected) {
                              next.removeAll(allFilteredIds);
                            } else {
                              next.addAll(allFilteredIds);
                            }
                            selectedTaskIds.value = next;
                          },
                          child: Text(
                            areAllFilteredSelected
                                ? 'Deselect All'
                                : 'Select All',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text(
                          'New Task',
                          style: TextStyle(fontSize: 12),
                        ),
                        onPressed: () => _openCreateTask(context, ref, goals),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Tasks List
                Expanded(
                  child: filtered.isEmpty
                      ? availableContexts.isEmpty
                          ? EmptyState(
                              emoji: '🎯',
                              title: 'No pending tasks in goals',
                              subtitle:
                                  'All tasks are completed or already scheduled for today.',
                              buttonLabel: '+ Create Task for Today',
                              onButton: () =>
                                  _openCreateTask(context, ref, goals),
                            )
                          : Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  searchQuery.value.isNotEmpty
                                      ? 'No tasks matching "${searchQuery.value}"'
                                      : 'No tasks for this goal',
                                  style: tt.bodyMedium?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final ctx = filtered[index];
                            final isSelected =
                                selectedTaskIds.value.contains(ctx.task.id);
                            return _SelectableTaskTile(
                              taskCtx: ctx,
                              isSelected: isSelected,
                              onToggle: () {
                                final next =
                                    Set<int>.from(selectedTaskIds.value);
                                if (isSelected) {
                                  next.remove(ctx.task.id);
                                } else {
                                  next.add(ctx.task.id);
                                }
                                selectedTaskIds.value = next;
                              },
                            );
                          },
                        ),
                ),

                // Bottom Action Bar
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    border: Border(top: BorderSide(color: cs.outline)),
                  ),
                  child: Row(
                    children: [
                      if (selectedTaskIds.value.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${selectedTaskIds.value.length} selected',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: cs.primary,
                              ),
                            ),
                          ),
                        ),
                      Expanded(
                        child: CustomButton(
                          label: selectedTaskIds.value.isEmpty
                              ? 'Select Tasks to Add'
                              : 'Add to Today (${selectedTaskIds.value.length})',
                          isLoading: isSaving.value,
                          onPressed:
                              selectedTaskIds.value.isEmpty ? null : addToToday,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openCreateTask(
    BuildContext context,
    WidgetRef ref,
    List<Goal> goals,
  ) {
    if (goals.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please create a goal first.')),
      );
      return;
    }

    showAdaptiveSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuickCreateTaskForTodaySheet(goals: goals),
    );
  }
}

class _GoalFilterChip extends StatelessWidget {
  final String? emoji;
  final String label;
  final Color? color;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  const _GoalFilterChip({
    this.emoji,
    required this.label,
    this.color,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (color ?? cs.primary).withValues(alpha: 0.16)
              : cs.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? (color ?? cs.primary) : cs.outline,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (emoji != null && emoji!.isNotEmpty) ...[
              Text(emoji!, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? (color ?? cs.primary) : cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? (color ?? cs.primary).withValues(alpha: 0.25)
                    : cs.outline.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isSelected
                      ? (color ?? cs.primary)
                      : cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectableTaskTile extends StatelessWidget {
  final TodayTaskContext taskCtx;
  final bool isSelected;
  final VoidCallback onToggle;

  const _SelectableTaskTile({
    required this.taskCtx,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final goalColor =
        Color(taskCtx.goal?.colorHex ?? cs.primary.toARGB32());
    final task = taskCtx.task;

    return Material(
      color: isSelected
          ? goalColor.withValues(alpha: 0.08)
          : cs.surfaceVariant,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? goalColor : cs.outline,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Checkbox(
                value: isSelected,
                activeColor: goalColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                onChanged: (_) => onToggle(),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            task.text,
                            style: tt.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (task.priority > 0) ...[
                          const SizedBox(width: 6),
                          _PriorityBadge(priority: task.priority),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: goalColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${taskCtx.goal?.emoji ?? ''} ${taskCtx.goal?.name ?? 'Goal'} · ${taskCtx.milestone?.title ?? 'Milestone'}',
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (task.dueDate != null) ...[
                const SizedBox(width: 8),
                DueDateBadge(contextData: taskCtx),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  final int priority;
  const _PriorityBadge({required this.priority});

  @override
  Widget build(BuildContext context) {
    final label = priority == 2 ? 'Critical' : 'High';
    final color =
        priority == 2 ? const Color(0xFFF87171) : const Color(0xFFFBBF24);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _QuickCreateTaskForTodaySheet extends HookConsumerWidget {
  final List<Goal> goals;

  const _QuickCreateTaskForTodaySheet({required this.goals});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final selectedGoal = useState<Goal>(goals.first);
    final milestonesAsync =
        ref.watch(milestonesForGoalProvider(selectedGoal.value.id));

    final textCtrl = useTextEditingController();
    final noteCtrl = useTextEditingController();
    final priority = useState(0);
    final selectedMilestoneId = useState<int?>(null);
    final isSaving = useState(false);
    final formKey = useMemoized(GlobalKey<FormState>.new);

    final milestones = milestonesAsync.valueOrNull ?? [];
    if (selectedMilestoneId.value == null && milestones.isNotEmpty) {
      selectedMilestoneId.value = milestones.first.id;
    }

    Future<void> save() async {
      if (!formKey.currentState!.validate()) return;
      if (selectedMilestoneId.value == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select or create a milestone first.'),
          ),
        );
        return;
      }

      isSaving.value = true;
      try {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        await TaskRepository.instance.create(
          milestoneId: selectedMilestoneId.value!,
          text: textCtrl.text.trim(),
          priority: priority.value,
          dueDate: today,
          note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
        );
        bumpActivityTick(ref);
        ref.invalidate(todayTasksGroupedProvider);
        if (context.mounted) {
          Navigator.of(context).pop(); // Close quick create
          Navigator.of(context).pop(1); // Close picker sheet with result 1
        }
      } finally {
        isSaving.value = false;
      }
    }

    final goalColor = Color(selectedGoal.value.colorHex);

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BottomSheetHandle(),
                Text(
                  'New Task for Today',
                  style:
                      tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),

                // Goal Dropdown
                Text('Goal',
                    style:
                        tt.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                DropdownButtonFormField<Goal>(
                  value: selectedGoal.value,
                  decoration: const InputDecoration(
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  items: goals.map((g) {
                    return DropdownMenuItem(
                      value: g,
                      child: Row(
                        children: [
                          Text(g.emoji),
                          const SizedBox(width: 8),
                          Text(g.name),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (g) {
                    if (g != null) {
                      selectedGoal.value = g;
                      selectedMilestoneId.value = null;
                    }
                  },
                ),
                const SizedBox(height: 14),

                // Milestone Dropdown
                Text('Milestone',
                    style:
                        tt.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                milestonesAsync.when(
                  loading: () =>
                      const Center(child: LinearProgressIndicator()),
                  error: (e, _) => Text('Error: $e'),
                  data: (msList) {
                    if (msList.isEmpty) {
                      return Text(
                        'No milestones found for this goal.',
                        style: tt.bodySmall?.copyWith(color: cs.error),
                      );
                    }
                    return DropdownButtonFormField<int>(
                      value: selectedMilestoneId.value ?? msList.first.id,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                      ),
                      items: msList.map((m) {
                        return DropdownMenuItem(
                          value: m.id,
                          child: Text(m.title),
                        );
                      }).toList(),
                      onChanged: (id) => selectedMilestoneId.value = id,
                    );
                  },
                ),
                const SizedBox(height: 14),

                // Task Text
                TextFormField(
                  controller: textCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Task *',
                    hintText: 'What are you working on today?',
                  ),
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Task text required'
                      : null,
                ),
                const SizedBox(height: 14),

                // Priority
                Text('Priority',
                    style:
                        tt.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Row(
                  children: List.generate(3, (i) {
                    final isSelected = priority.value == i;
                    final labels = ['Normal', 'High', 'Critical'];
                    final colors = [
                      const Color(0xFF5A6A92),
                      const Color(0xFFFBBF24),
                      const Color(0xFFF87171),
                    ];
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => priority.value = i,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? colors[i].withValues(alpha: 0.2)
                                  : cs.surfaceVariant,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected ? colors[i] : cs.outline,
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              labels[i],
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isSelected
                                    ? colors[i]
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 24),

                CustomButton(
                  label: 'Add to Today',
                  isLoading: isSaving.value,
                  color: goalColor,
                  onPressed: save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
