import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:confetti/confetti.dart';
import '../../../core/models/models.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/progress_utils.dart';
import '../../../shared/widgets/animated_checkbox.dart';
import '../../../shared/widgets/confirmation_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/progress_bar.dart';
import '../../../shared/widgets/progress_ring.dart';
import '../../ai_coach/presentation/adjust_plan_sheet.dart';
import '../../ai_coach/presentation/coach_chat_sheet.dart';
import '../../ai_coach/presentation/goal_coach_section.dart';
import '../../ai_coach/providers/ai_coach_provider.dart';
import '../../goals/data/goal_repository.dart';
import '../../goals/presentation/widgets/create_edit_goal_sheet.dart';
import '../../goals/providers/goal_provider.dart';
import '../../milestones/data/milestone_repository.dart';
import '../../milestones/providers/milestone_provider.dart';
import '../../tasks/data/task_repository.dart';
import '../../tasks/providers/task_provider.dart';
import 'widgets/create_edit_milestone_sheet.dart';
import 'widgets/create_edit_task_sheet.dart';

class GoalDetailScreen extends ConsumerStatefulWidget {
  final int goalId;
  const GoalDetailScreen({super.key, required this.goalId});

  @override
  ConsumerState<GoalDetailScreen> createState() => _GoalDetailScreenState();
}

class _GoalDetailScreenState extends ConsumerState<GoalDetailScreen> {
  late ConfettiController _confetti;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 2));
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final goalAsync = ref.watch(goalByIdProvider(widget.goalId));

    return goalAsync.when(
      loading: () => Scaffold(
        backgroundColor: cs.background,
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(child: Text('Error: $e')),
      ),
      data: (goal) {
        if (goal == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.pop();
          });
          return const Scaffold(body: SizedBox.shrink());
        }
        return _GoalDetailBody(
          goal: goal,
          confettiController: _confetti,
        );
      },
    );
  }
}

class _GoalDetailBody extends ConsumerWidget {
  final Goal goal;
  final ConfettiController confettiController;

  const _GoalDetailBody({
    required this.goal,
    required this.confettiController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final goalColor = Color(goal.colorHex);
    final hasAiCoach = ref.watch(hasAiCoachProvider);

    return Scaffold(
      backgroundColor: cs.background,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // ── AppBar ──────────────────────────────────────
              SliverAppBar(
                expandedHeight: 200,
                pinned: true,
                backgroundColor: cs.background,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new),
                  onPressed: () => context.pop(),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.center_focus_strong_outlined),
                    tooltip: 'Focus Mode',
                    onPressed: () => context.push('/focus/${goal.id}'),
                  ),
                  if (hasAiCoach) ...[
                    IconButton(
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                      tooltip: 'Coach Chat',
                      onPressed: () => showCoachChatSheet(context, goal.id),
                    ),
                    IconButton(
                      icon: const Icon(Icons.auto_fix_high_outlined),
                      tooltip: 'Adjust Plan',
                      onPressed: () => showAdjustPlanSheet(context, goal.id),
                    ),
                  ],
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => CreateEditGoalSheet(goal: goal),
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) => _handleMenu(context, ref, v),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'archive',
                        child: Row(children: [
                          const Icon(Icons.archive_outlined),
                          const SizedBox(width: 8),
                          Text(goal.isArchived ? 'Unarchive' : 'Archive'),
                        ]),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          Icon(Icons.delete_outline, color: cs.error),
                          const SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: cs.error)),
                        ]),
                      ),
                    ],
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: _GoalHeroHeader(
                    goal: goal,
                    goalColor: goalColor,
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: GoalCoachSection(goalId: goal.id),
                ),
              ),

              // ── Milestones ───────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Milestones',
                          style: tt.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add'),
                        onPressed: () => _addMilestone(context),
                      ),
                    ],
                  ),
                ),
              ),

              _MilestonesList(
                goalId: goal.id,
                goalColor: goalColor,
                onMilestoneComplete: () => confettiController.play(),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),

          // ── Confetti ─────────────────────────────────────────
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              numberOfParticles: 30,
              gravity: 0.3,
              colors: const [
                Color(0xFF5B9CF6),
                Color(0xFF34D399),
                Color(0xFFFBBF24),
                Color(0xFFF472B6),
                Color(0xFFA78BFA),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addMilestone(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreateEditMilestoneSheet(goalId: goal.id),
    );
  }

  Future<void> _handleMenu(
      BuildContext context, WidgetRef ref, String action) async {
    if (action == 'archive') {
      if (goal.isArchived) {
        await GoalRepository.instance.unarchive(goal.id);
      } else {
        await GoalRepository.instance.archive(goal.id);
      }
    } else if (action == 'delete') {
      final ok = await ConfirmationDialog.show(
        context,
        title: 'Delete Goal',
        message: 'Delete "${goal.name}" and all its data?',
      );
      if (ok && context.mounted) {
        await GoalRepository.instance.delete(goal.id);
        context.pop();
      }
    }
  }
}

// ── Hero header ───────────────────────────────────────────

class _GoalHeroHeader extends ConsumerWidget {
  final Goal goal;
  final Color goalColor;

  const _GoalHeroHeader({required this.goal, required this.goalColor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final milestonesAsync = ref.watch(milestonesForGoalProvider(goal.id));
    final progress = milestonesAsync.when(
      loading: () => const _DetailProgress(0, 0, 0, 0),
      error: (_, __) => const _DetailProgress(0, 0, 0, 0),
      data: (milestones) {
        int total = 0;
        int done = 0;
        final completedDates = <DateTime>[];

        for (final ms in milestones) {
          final tasks =
              ref.watch(tasksForMilestoneProvider(ms.id)).valueOrNull ??
                  const <Task>[];
          total += tasks.length;
          for (final task in tasks) {
            if (task.isCompleted) {
              done++;
              if (task.completedAt != null)
                completedDates.add(task.completedAt!);
            }
          }
        }

        return _DetailProgress(
          ProgressUtils.goalProgress(totalTasks: total, completedTasks: done),
          done,
          total,
          ProgressUtils.calculateStreak(completedDates),
        );
      },
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 90, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            goalColor.withOpacity(0.15),
            cs.background,
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Progress ring
          ProgressRing(
            percent: progress.percent,
            color: goalColor,
            size: 80,
            strokeWidth: 7,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(progress.percent * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: goalColor,
                  ),
                ),
              ],
            ),
          ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(goal.emoji, style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        goal.name,
                        style: tt.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${progress.done}/${progress.total} tasks done',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (progress.streak > 0) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFB923C).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '🔥 ${progress.streak}d streak',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFFFB923C),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: goalColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        AppDateUtils.daysUntilLabel(goal.targetDate),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: goalColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Milestones list ───────────────────────────────────────

class _MilestonesList extends ConsumerStatefulWidget {
  final int goalId;
  final Color goalColor;
  final VoidCallback onMilestoneComplete;

  const _MilestonesList({
    required this.goalId,
    required this.goalColor,
    required this.onMilestoneComplete,
  });

  @override
  ConsumerState<_MilestonesList> createState() => _MilestonesListState();
}

class _MilestonesListState extends ConsumerState<_MilestonesList> {
  final Map<int, bool> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final msAsync = ref.watch(milestonesForGoalProvider(widget.goalId));

    return msAsync.when(
      loading: () => const SliverToBoxAdapter(
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) =>
          SliverToBoxAdapter(child: Center(child: Text('Error: $e'))),
      data: (milestones) {
        if (milestones.isEmpty) {
          return SliverToBoxAdapter(
            child: EmptyState(
              emoji: '🗺️',
              title: 'No milestones yet',
              subtitle: 'Break your goal into milestones to track progress.',
            ),
          );
        }
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          sliver: SliverReorderableList(
            itemCount: milestones.length,
            onReorder: (oldIndex, newIndex) async {
              final list = [...milestones];
              if (newIndex > oldIndex) newIndex--;
              final item = list.removeAt(oldIndex);
              list.insert(newIndex, item);
              await MilestoneRepository.instance.reorder(list);
            },
            itemBuilder: (context, i) {
              final ms = milestones[i];
              return ReorderableDelayedDragStartListener(
                key: ValueKey(ms.id),
                index: i,
                child: _MilestoneCard(
                  milestone: ms,
                  goalColor: widget.goalColor,
                  onComplete: widget.onMilestoneComplete,
                  isExpanded: _expanded[ms.id] ?? false,
                  onToggle: () => setState(
                    () => _expanded[ms.id] = !(_expanded[ms.id] ?? false),
                  ),
                ).animate().fadeIn(delay: (i * 40).ms).slideY(begin: 0.05),
              );
            },
          ),
        );
      },
    );
  }
}

// ── Milestone card ────────────────────────────────────────

class _MilestoneCard extends ConsumerWidget {
  final Milestone milestone;
  final Color goalColor;
  final VoidCallback onComplete;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _MilestoneCard({
    required this.milestone,
    required this.goalColor,
    required this.onComplete,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tasksAsync =
        ref.watch(tasksForMilestoneProvider(milestone.id));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Slidable(
        key: ValueKey(milestone.id),
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          children: [
            SlidableAction(
              onPressed: (_) => _deleteMilestone(context),
              backgroundColor: cs.error,
              foregroundColor: Colors.white,
              icon: Icons.delete_outline,
              label: 'Delete',
              borderRadius: BorderRadius.circular(14),
            ),
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            color: cs.surfaceVariant,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Milestone header ────────────────────────────
              InkWell(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(14)),
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: tasksAsync.when(
                    loading: () => _MilestoneHeader(
                      milestone: milestone,
                      goalColor: goalColor,
                      expanded: isExpanded,
                      done: 0,
                      total: 0,
                    ),
                    error: (_, __) => Text(milestone.title),
                    data: (tasks) {
                      final done = tasks.where((t) => t.isCompleted).length;
                      final total = tasks.length;
                      return _MilestoneHeader(
                        milestone: milestone,
                        goalColor: goalColor,
                        expanded: isExpanded,
                        done: done,
                        total: total,
                      );
                    },
                  ),
                ),
              ),

              // ── Tasks ────────────────────────────────────────
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: isExpanded
                    ? tasksAsync.when(
                        loading: () => const Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ),
                        error: (_, __) => const SizedBox.shrink(),
                        data: (tasks) => _TasksList(
                          tasks: tasks,
                          milestone: milestone,
                          goalColor: goalColor,
                          onComplete: onComplete,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteMilestone(BuildContext context) async {
    final ok = await ConfirmationDialog.show(
      context,
      title: 'Delete Milestone',
      message:
          'Delete "${milestone.title}" and all its tasks? This cannot be undone.',
    );
    if (ok) {
      await MilestoneRepository.instance.delete(milestone.id);
    }
  }
}

class _MilestoneHeader extends StatelessWidget {
  final Milestone milestone;
  final Color goalColor;
  final bool expanded;
  final int done;
  final int total;

  const _MilestoneHeader({
    required this.milestone,
    required this.goalColor,
    required this.expanded,
    required this.done,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final percent = total == 0 ? 0.0 : done / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(milestone.title,
                      style:
                          tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  if (milestone.theme.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: goalColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        milestone.theme,
                        style: TextStyle(
                          fontSize: 11,
                          color: goalColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Text(
              '$done/$total',
              style: tt.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: goalColor,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              color: cs.onSurfaceVariant,
              size: 20,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ProgressBar(percent: percent, color: goalColor, height: 4),
      ],
    );
  }
}

// ── Tasks list inside milestone ───────────────────────────

class _TasksList extends ConsumerWidget {
  final List<Task> tasks;
  final Milestone milestone;
  final Color goalColor;
  final VoidCallback onComplete;

  const _TasksList({
    required this.tasks,
    required this.milestone,
    required this.goalColor,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(height: 1, color: cs.outline),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorder: (oldIndex, newIndex) async {
            final list = [...tasks];
            if (newIndex > oldIndex) newIndex--;
            final item = list.removeAt(oldIndex);
            list.insert(newIndex, item);
            await TaskRepository.instance.reorder(list);
          },
          itemCount: tasks.length,
          itemBuilder: (context, i) {
            final task = tasks[i];
            return ReorderableDelayedDragStartListener(
              key: ValueKey(task.id),
              index: i,
              child: _TaskRow(
                task: task,
                goalColor: goalColor,
                onComplete: onComplete,
              ).animate().fadeIn(delay: (i * 20).ms),
            );
          },
        ),
        // Add task button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: GestureDetector(
            onTap: () => _openAddTask(context),
            child: Row(
              children: [
                Icon(Icons.add_circle_outline, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text('Add task',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.primary,
                      fontWeight: FontWeight.w500,
                    )),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _openAddTask(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          CreateEditTaskSheet(milestoneId: milestone.id, goalColor: goalColor),
    );
  }
}

// ── Task row ──────────────────────────────────────────────

class _TaskRow extends ConsumerWidget {
  final Task task;
  final Color goalColor;
  final VoidCallback onComplete;

  const _TaskRow({
    required this.task,
    required this.goalColor,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Slidable(
      key: ValueKey(task.id),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        children: [
          SlidableAction(
            onPressed: (_) => _deleteTask(context),
            backgroundColor: cs.error,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline,
            label: 'Delete',
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _openEdit(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedCheckbox(
                checked: task.isCompleted,
                color: goalColor,
                onToggle: () => _toggleTask(ref),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.text,
                      style: tt.bodyMedium?.copyWith(
                        decoration: task.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                        color: task.isCompleted
                            ? cs.onSurfaceVariant
                            : cs.onBackground,
                      ),
                    ),
                    if (task.note != null && task.note!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        task.note!,
                        style: tt.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              // Priority dot
              _PriorityDot(priority: task.priority),
              // Note icon
              if (task.note != null && task.note!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child:
                      Icon(Icons.notes, size: 14, color: cs.onSurfaceVariant),
                ),

            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleTask(WidgetRef ref) async {
    final wasCompleted = task.isCompleted;
    HapticFeedback.lightImpact();
    await TaskRepository.instance.toggleComplete(task.id);
    if (!wasCompleted) {
      HapticFeedback.mediumImpact();
      // Check if milestone is now complete
      final tasks = await TaskRepository.instance
          .getForMilestone(task.milestone.value?.id ?? 0);
      if (tasks.isNotEmpty && tasks.every((t) => t.isCompleted)) {
        HapticFeedback.heavyImpact();
        onComplete();
      }
    }
  }

  Future<void> _deleteTask(BuildContext context) async {
    final ok = await ConfirmationDialog.show(
      context,
      title: 'Delete Task',
      message: 'Delete this task? This cannot be undone.',
    );
    if (ok) await TaskRepository.instance.delete(task.id);
  }

  void _openEdit(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreateEditTaskSheet(
        milestoneId: task.milestone.value?.id ?? 0,
        goalColor: goalColor,
        task: task,
      ),
    );
  }
}

// ── Priority dot ──────────────────────────────────────────

class _PriorityDot extends StatelessWidget {
  final int priority;
  const _PriorityDot({required this.priority});

  @override
  Widget build(BuildContext context) {
    final color = switch (priority) {
      2 => const Color(0xFFF87171),
      1 => const Color(0xFFFBBF24),
      _ => Theme.of(context).colorScheme.outline,
    };
    return Container(
      width: 8,
      height: 8,
      margin: const EdgeInsets.only(top: 4, left: 4),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// ── Progress provider for goal detail ─────────────────────

class _DetailProgress {
  final double percent;
  final int done;
  final int total;
  final int streak;
  const _DetailProgress(this.percent, this.done, this.total, this.streak);
}
