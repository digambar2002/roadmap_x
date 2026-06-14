import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/models/models.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/progress_utils.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/progress_bar.dart';
import '../../../shared/widgets/progress_ring.dart';
import '../../../shared/widgets/confirmation_dialog.dart';
import '../../ai_goal/presentation/ai_goal_sheet.dart';
import '../../milestones/providers/milestone_provider.dart';
import '../../tasks/providers/task_provider.dart';
import '../providers/goal_provider.dart';
import '../data/goal_repository.dart';
import 'widgets/create_edit_goal_sheet.dart';
import 'widgets/goal_template_sheet.dart';

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final filter = ref.watch(goalFilterProvider);
    final goalsAsync = ref.watch(filteredGoalsProvider);

    return Scaffold(
      backgroundColor: cs.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: goalsAsync.when(
                      data: (goals) => Text(
                        'My Goals (${goals.length})',
                        style: tt.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      loading: () => Text('My Goals',
                          style: tt.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      error: (_, __) => const Text('My Goals'),
                    ),
                  ),
                  // Settings icon goes to settings
                  IconButton(
                    icon: Icon(Icons.settings_outlined,
                        color: cs.onSurfaceVariant),
                    onPressed: () => context.push('/settings'),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.1),

            // ── Filter chips ─────────────────────────────────
            _FilterChips(
              current: filter,
              onChanged: (f) => ref.read(goalFilterProvider.notifier).state = f,
            ).animate().fadeIn(delay: 100.ms),

            // ── Goals list ───────────────────────────────────
            Expanded(
              child: goalsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (goals) => goals.isEmpty
                    ? EmptyState(
                        emoji: '🎯',
                        title: 'No goals yet',
                        subtitle: 'Start by creating your first goal.',
                        buttonLabel: '+ Create Goal',
                        onButton: () => _openCreate(context, ref),
                      )
                    : _GoalsList(goals: goals),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF5B9CF6), Color(0xFFA78BFA)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF5B9CF6).withOpacity(0.35),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          heroTag: 'goals_fab',
          elevation: 0,
          backgroundColor: Colors.transparent,
          onPressed: () => _showOptions(context, ref),
          icon: const Icon(Icons.auto_awesome, color: Colors.white),
          label: const Text(
            'New Goal',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ).animate().scale(delay: 200.ms),
    );
  }

  void _openCreate(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CreateEditGoalSheet(),
    );
  }

  Future<void> _openAi(BuildContext context) async {
    final goalId = await showAiGoalSheet(context);
    if (!context.mounted || goalId == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🎉 Goal created! Start working on it.')),
    );
    context.go('/goals/$goalId');
  }

  void _showOptions(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFF5B9CF6), Color(0xFFA78BFA)],
                ).createShader(bounds),
                child: const Icon(Icons.auto_awesome, color: Colors.white),
              ),
              title: const Text(
                '✦ Generate with AI',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Describe your goal, AI builds the plan'),
              onTap: () {
                Navigator.pop(context);
                _openAi(context);
              },
            ),
            Divider(color: cs.outline),
            ListTile(
              leading: Icon(Icons.library_books_outlined,
                  color: cs.onSurfaceVariant),
              title: const Text('Use Template'),
              subtitle: const Text('Create from proven goal structure'),
              onTap: () async {
                Navigator.pop(context);
                final goalId = await showGoalTemplateSheet(context);
                if (goalId != null && context.mounted) {
                  context.go('/goals/$goalId');
                }
              },
            ),
            Divider(color: cs.outline),
            ListTile(
              leading: Icon(Icons.edit_outlined, color: cs.onSurfaceVariant),
              title: const Text('Create Manually'),
              subtitle: const Text('Set up your own goal and milestones'),
              onTap: () {
                Navigator.pop(context);
                _openCreate(context, ref);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Filter chips ──────────────────────────────────────────

class _FilterChips extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChanged;

  const _FilterChips({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const filters = ['active', 'all', 'archived'];
    const labels = {'active': 'Active', 'all': 'All', 'archived': 'Archived'};

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: filters.map((f) {
          final selected = current == f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(labels[f]!),
              selected: selected,
              onSelected: (_) => onChanged(f),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Goals list ────────────────────────────────────────────

class _GoalsList extends ConsumerWidget {
  final List<Goal> goals;
  const _GoalsList({required this.goals});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: goals.length,
      proxyDecorator: (child, index, animation) => Material(
        color: Colors.transparent,
        child: child,
      ),
      onReorder: (oldIndex, newIndex) async {
        if (newIndex > oldIndex) newIndex--;
        final reordered = List<Goal>.from(goals);
        final item = reordered.removeAt(oldIndex);
        reordered.insert(newIndex, item);
        await GoalRepository.instance.reorder(reordered);
      },
      itemBuilder: (context, i) {
        final goal = goals[i];
        return KeyedSubtree(
          key: ValueKey(goal.id),
          child: _GoalCard(
            goal: goal,
          ).animate().fadeIn(delay: (i * 40).ms).slideY(begin: 0.05),
        );
      },
    );
  }
}

// ── Goal card ─────────────────────────────────────────────

class _GoalCard extends ConsumerWidget {
  final Goal goal;
  const _GoalCard({required this.goal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final goalColor = Color(goal.colorHex);
    final milestonesAsync = ref.watch(milestonesForGoalProvider(goal.id));
    final progress = milestonesAsync.when(
      loading: () => const _Progress(0, 0, 0),
      error: (_, __) => const _Progress(0, 0, 0),
      data: (milestones) {
        int total = 0;
        int done = 0;

        for (final ms in milestones) {
          final tasks =
              ref.watch(tasksForMilestoneProvider(ms.id)).valueOrNull ??
                  const <Task>[];
          total += tasks.length;
          done += tasks.where((t) => t.isCompleted).length;
        }

        return _Progress(
          ProgressUtils.goalProgress(totalTasks: total, completedTasks: done),
          done,
          total,
          milestones.length,
        );
      },
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Slidable(
        key: ValueKey(goal.id),
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          children: [
            SlidableAction(
              onPressed: (_) => _delete(context, ref),
              backgroundColor: cs.error,
              foregroundColor: Colors.white,
              icon: Icons.delete_outline,
              label: 'Delete',
              borderRadius: BorderRadius.circular(14),
            ),
          ],
        ),
        startActionPane: ActionPane(
          motion: const DrawerMotion(),
          children: [
            SlidableAction(
              onPressed: (_) => _archive(ref),
              backgroundColor: const Color(0xFFFBBF24),
              foregroundColor: Colors.white,
              icon: goal.isArchived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined,
              label: goal.isArchived ? 'Unarchive' : 'Archive',
              borderRadius: BorderRadius.circular(14),
            ),
          ],
        ),
        child: GestureDetector(
          onTap: () => context.push('/goals/${goal.id}'),
          child: Container(
            decoration: BoxDecoration(
              color: cs.surfaceVariant,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outline),
            ),
            child: Column(
              children: [
                // Color accent bar
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: goalColor,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Emoji + name
                          Text(goal.emoji,
                              style: const TextStyle(fontSize: 28)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  goal.name,
                                  style: tt.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (goal.description.isNotEmpty)
                                  Text(
                                    goal.description,
                                    style: tt.bodySmall,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          // Progress ring
                          ProgressRing(
                            percent: progress.percent,
                            color: goalColor,
                            size: 44,
                            strokeWidth: 4,
                            child: Text(
                              '${(progress.percent * 100).toInt()}%',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: goalColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ProgressBar(
                        percent: progress.percent,
                        color: goalColor,
                        height: 5,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(Icons.flag_outlined,
                              size: 13, color: cs.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            '${progress.milestones} milestones · ${progress.done}/${progress.total} tasks',
                            style: tt.bodySmall,
                          ),
                          const Spacer(),
                          _DateBadge(
                            date: goal.targetDate,
                            color: goalColor,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await ConfirmationDialog.show(
      context,
      title: 'Delete Goal',
      message:
          'Delete "${goal.name}" and all its milestones and tasks? This cannot be undone.',
    );
    if (!confirmed) return;
    await GoalRepository.instance.delete(goal.id);
  }

  Future<void> _archive(WidgetRef ref) async {
    if (goal.isArchived) {
      await GoalRepository.instance.unarchive(goal.id);
    } else {
      await GoalRepository.instance.archive(goal.id);
    }
  }
}

// ── Progress provider for a single goal ───────────────────

class _Progress {
  final double percent;
  final int done;
  final int total;
  final int milestones;
  const _Progress(this.percent, this.done, this.total, [this.milestones = 0]);
}

// ── Date badge ────────────────────────────────────────────

class _DateBadge extends StatelessWidget {
  final DateTime date;
  final Color color;
  const _DateBadge({required this.date, required this.color});

  @override
  Widget build(BuildContext context) {
    final label = AppDateUtils.daysUntilLabel(date);
    final days = AppDateUtils.daysUntil(date);
    final badgeColor = days < 0
        ? const Color(0xFFF87171)
        : days <= 7
            ? const Color(0xFFFBBF24)
            : color;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: badgeColor.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: badgeColor,
        ),
      ),
    );
  }
}
