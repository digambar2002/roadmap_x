import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/layout/adaptive_page.dart';
import '../../../core/models/habit_icons.dart';
import '../../../core/models/models.dart';
import '../../../core/services/habit_customization_service.dart';
import '../../../shared/widgets/animated_checkbox.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../analytics/providers/activity_provider.dart';
import '../providers/habit_provider.dart';
import 'widgets/habit_calendar_row.dart';
import 'widgets/habit_edit_sheet.dart';

/// A modern, full-featured Habit Tracker screen.
///
/// Features:
/// - 7-day interactive calendar strip with selected day highlight
/// - Top Habits weekly consistency progress bars
/// - Filter chips (To Do, Completed, All)
/// - Categorized sections (Morning, Workload, Night, Anytime)
/// - Custom colors, icons, repeat rules, and notifications
class HabitsScreen extends ConsumerStatefulWidget {
  const HabitsScreen({super.key});

  @override
  ConsumerState<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends ConsumerState<HabitsScreen> {
  DateTime _selectedDate = DateTime.now();
  String _filter = 'All'; // 'All', 'To Do', 'Completed'

  DateTime get _normalizedSelectedDate =>
      DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);

  bool get _isViewingToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  Future<void> _toggleHabit(String habitUid, Set<String> currentChecked) async {
    HapticFeedback.lightImpact();
    final isChecked = currentChecked.contains(habitUid);
    final targetDate = _normalizedSelectedDate;
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

    final habitsAsync = ref.watch(habitsProvider);
    ref.watch(habitCustomizationVersionProvider);
    final checkedAsync = ref.watch(habitChecksForDateProvider(_normalizedSelectedDate));
    final streakAsync = ref.watch(habitStreakProvider);
    final weeklyProgressAsync = ref.watch(habitWeeklyProgressProvider);

    final now = DateTime.now();
    final startOfWeek = _normalizedSelectedDate
        .subtract(Duration(days: _normalizedSelectedDate.weekday - 1));
    final completedDaysAsync =
        ref.watch(habitCompletedDaysInWeekProvider(startOfWeek));

    final streak = streakAsync.valueOrNull ?? 0;
    final checked = checkedAsync.valueOrNull ?? const <String>{};
    final weeklyProgress = weeklyProgressAsync.valueOrNull ?? const <String, int>{};
    final completedDays = completedDaysAsync.valueOrNull ?? const <String>{};

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Habit Tracker',
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (streak > 0)
              Text(
                '🔥 $streak day streak',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFF59E0B),
                ),
              ),
          ],
        ),
        backgroundColor: cs.surface,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Add habit',
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.add_rounded, color: cs.primary, size: 20),
            ),
            onPressed: () => HabitEditSheet.show(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AdaptivePage(
        child: habitsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('Error: $error')),
          data: (habits) {
            if (habits.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: EmptyState(
                    emoji: '🎯',
                    title: 'No habits yet',
                    subtitle:
                        'Build consistent routines with custom colors, '
                        'repeat schedules, and daily reminders.',
                    buttonLabel: 'Add your first habit',
                    onButton: () => HabitEditSheet.show(context),
                  ),
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: () async {
                ref.read(habitActivityTickProvider.notifier).state++;
                ref.read(activityTickProvider.notifier).state++;
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                children: [
                  // ── Calendar Week Row ─────────────────────────────
                  HabitCalendarRow(
                    selectedDate: _selectedDate,
                    onDateSelected: (date) {
                      setState(() => _selectedDate = date);
                    },
                    completedDates: completedDays,
                  ),
                  const SizedBox(height: 16),

                  // ── Filter Tabs ───────────────────────────────────
                  Row(
                    children: [
                      _FilterTab(
                        label: 'All',
                        isSelected: _filter == 'All',
                        onTap: () => setState(() => _filter = 'All'),
                      ),
                      const SizedBox(width: 8),
                      _FilterTab(
                        label: 'To Do',
                        isSelected: _filter == 'To Do',
                        onTap: () => setState(() => _filter = 'To Do'),
                      ),
                      const SizedBox(width: 8),
                      _FilterTab(
                        label: 'Completed',
                        isSelected: _filter == 'Completed',
                        onTap: () => setState(() => _filter = 'Completed'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Top Habits Weekly Consistency ─────────────────
                  if (habits.length >= 2) ...[
                    _TopHabitsSection(
                      habits: habits,
                      weeklyProgress: weeklyProgress,
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── Categorized Habits ────────────────────────────
                  _CategorizedHabitsList(
                    habits: habits,
                    checked: checked,
                    filter: _filter,
                    selectedDate: _normalizedSelectedDate,
                    onToggle: (uid) => _toggleHabit(uid, checked),
                    onEdit: (habit) => HabitEditSheet.show(context, habit: habit),
                    onAddInCategory: (cat) =>
                        HabitEditSheet.show(context, initialCategory: cat),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'habits_screen_fab',
        onPressed: () => HabitEditSheet.show(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Habit'),
      ),
    );
  }
}

class _FilterTab extends StatelessWidget {
  const _FilterTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? cs.primary
              : cs.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outline.withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// "Top Habits" section with weekly progress bars (6/7, 5/7) like reference image.
class _TopHabitsSection extends StatelessWidget {
  const _TopHabitsSection({
    required this.habits,
    required this.weeklyProgress,
  });

  final List<Habit> habits;
  final Map<String, int> weeklyProgress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // Pick top habits
    final top = habits.take(3).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Top Habits (This Week)',
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                'Weekly Goal',
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final habit in top) ...[
            _TopHabitRow(
              habit: habit,
              daysCompleted: weeklyProgress[habit.uid] ?? 0,
            ),
            if (habit != top.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _TopHabitRow extends ConsumerWidget {
  const _TopHabitRow({
    required this.habit,
    required this.daysCompleted,
  });

  final Habit habit;
  final int daysCompleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final customAsync = ref.watch(habitCustomizationProvider(habit.uid));
    final custom = customAsync.valueOrNull ?? const HabitCustomization();

    final pct = (daysCompleted / 7).clamp(0.0, 1.0);

    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: custom.color.withValues(alpha: 0.16),
            shape: BoxShape.circle,
          ),
          child: Icon(
            HabitIcons.resolve(habit.iconKey),
            size: 18,
            color: custom.color,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                habit.label.isEmpty ? 'Unnamed' : habit.label,
                style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 4,
                  backgroundColor: cs.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(custom.color),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '$daysCompleted/7',
          style: tt.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: custom.color,
          ),
        ),
      ],
    );
  }
}

/// Habits grouped into categories (Morning, Workload, Night, Anytime).
class _CategorizedHabitsList extends ConsumerWidget {
  const _CategorizedHabitsList({
    required this.habits,
    required this.checked,
    required this.filter,
    required this.selectedDate,
    required this.onToggle,
    required this.onEdit,
    required this.onAddInCategory,
  });

  final List<Habit> habits;
  final Set<String> checked;
  final String filter;
  final DateTime selectedDate;
  final ValueChanged<String> onToggle;
  final ValueChanged<Habit> onEdit;
  final ValueChanged<String> onAddInCategory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const categories = HabitCustomization.presetCategories;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final category in categories) ...[
          _CategoryGroup(
            category: category,
            habits: habits,
            checked: checked,
            filter: filter,
            selectedDate: selectedDate,
            onToggle: onToggle,
            onEdit: onEdit,
            onAdd: () => onAddInCategory(category),
          ),
        ],
      ],
    );
  }
}

class _CategoryGroup extends ConsumerWidget {
  const _CategoryGroup({
    required this.category,
    required this.habits,
    required this.checked,
    required this.filter,
    required this.selectedDate,
    required this.onToggle,
    required this.onEdit,
    required this.onAdd,
  });

  final String category;
  final List<Habit> habits;
  final Set<String> checked;
  final String filter;
  final DateTime selectedDate;
  final ValueChanged<String> onToggle;
  final ValueChanged<Habit> onEdit;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // Filter habits by category
    final matched = <Habit>[];
    for (final h in habits) {
      final custom = ref.watch(habitCustomizationProvider(h.uid)).valueOrNull ??
          const HabitCustomization();
      if (custom.category == category) {
        final isDone = checked.contains(h.uid);
        if (filter == 'To Do' && isDone) continue;
        if (filter == 'Completed' && !isDone) continue;
        matched.add(h);
      }
    }

    if (matched.isEmpty && filter != 'All') return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category header
          Row(
            children: [
              Text(
                category.toUpperCase(),
                style: tt.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${matched.length}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                icon: Icon(Icons.add_rounded, color: cs.primary),
                tooltip: 'Add in $category',
                onPressed: onAdd,
              ),
            ],
          ),
          const SizedBox(height: 6),

          if (matched.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'No habits in $category yet',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            )
          else
            Column(
              children: [
                for (final habit in matched) ...[
                  _HabitItemCard(
                    habit: habit,
                    isDone: checked.contains(habit.uid),
                    onToggle: () => onToggle(habit.uid),
                    onTap: () => onEdit(habit),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _HabitItemCard extends ConsumerWidget {
  const _HabitItemCard({
    required this.habit,
    required this.isDone,
    required this.onToggle,
    required this.onTap,
  });

  final Habit habit;
  final bool isDone;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final custom = ref.watch(habitCustomizationProvider(habit.uid)).valueOrNull ??
        const HabitCustomization();

    final habitColor = custom.color;

    return Material(
      color: isDone
          ? habitColor.withValues(alpha: 0.08)
          : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onToggle,
        onLongPress: onTap,
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
              // Habit Icon token with custom color (Tap icon to edit)
              GestureDetector(
                onTap: onTap,
                child: Tooltip(
                  message: 'Edit habit',
                  child: Container(
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
                        decoration: isDone ? TextDecoration.lineThrough : null,
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
    );
  }
}
