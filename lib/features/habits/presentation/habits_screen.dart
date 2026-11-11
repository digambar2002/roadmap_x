import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/layout/adaptive_page.dart';
import '../../../core/models/habit_icons.dart';
import '../../../core/models/models.dart';
import '../../../core/services/habit_customization_service.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../analytics/providers/activity_provider.dart';
import '../providers/habit_provider.dart';
import 'widgets/habit_calendar_row.dart';
import 'widgets/habit_edit_sheet.dart';
import 'widgets/habit_month_calendar.dart';
import 'widgets/habit_row.dart';
import '../../../shared/widgets/item_actions.dart';

/// A modern, full-featured Habit Tracker screen.
///
/// Features:
/// - 7-day interactive calendar strip with selected day highlight
/// - Filter tabs (All, To Do, Completed, Analytics)
/// - Categorized sections (Morning, Workload, Night, Anytime), only those
///   that have habits
/// - Analytics: every habit with its stats; tap one for a month calendar
/// - Custom colors, icons, repeat rules, and notifications
class HabitsScreen extends ConsumerStatefulWidget {
  const HabitsScreen({super.key});

  @override
  ConsumerState<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends ConsumerState<HabitsScreen> {
  DateTime _selectedDate = DateTime.now();
  String _filter = 'All'; // 'All', 'To Do', 'Completed', 'Analytics'

  DateTime get _normalizedSelectedDate =>
      DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);

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
    final checkedAsync =
        ref.watch(habitChecksForDateProvider(_normalizedSelectedDate));
    final streakAsync = ref.watch(habitStreakProvider);

    final startOfWeek = _normalizedSelectedDate
        .subtract(Duration(days: _normalizedSelectedDate.weekday - 1));
    final completedDaysAsync =
        ref.watch(habitCompletedDaysInWeekProvider(startOfWeek));

    final streak = streakAsync.valueOrNull ?? 0;
    final checked = checkedAsync.valueOrNull ?? const <String>{};
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
                    subtitle: 'Build consistent routines with custom colors, '
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
                  // ── Calendar Week Row (day views only) ─────────────
                  if (_filter != 'Analytics') ...[
                    HabitCalendarRow(
                      selectedDate: _selectedDate,
                      onDateSelected: (date) {
                        setState(() => _selectedDate = date);
                      },
                      completedDates: completedDays,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Filter Tabs ───────────────────────────────────
                  // Equal-width segments, so all four always fit on a phone.
                  Row(
                    children: [
                      for (final (i, label) in const [
                        'All',
                        'To Do',
                        'Completed',
                        'Analytics',
                      ].indexed) ...[
                        if (i > 0) const SizedBox(width: 6),
                        Expanded(
                          child: _FilterTab(
                            label: label,
                            isSelected: _filter == label,
                            onTap: () => setState(() => _filter = label),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Analytics or categorized habits ────────────────
                  if (_filter == 'Analytics')
                    _HabitAnalyticsList(habits: habits)
                  else
                    _CategorizedHabitsList(
                      habits: habits,
                      checked: checked,
                      filter: _filter,
                      selectedDate: _normalizedSelectedDate,
                      onToggle: (uid) => _toggleHabit(uid, checked),
                      onEdit: (habit) =>
                          HabitEditSheet.show(context, habit: habit),
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
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? cs.primary
              : cs.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outline.withValues(alpha: 0.5),
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
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

    // With empty sections hidden, make sure the list never goes silently
    // blank: say why when nothing matches the selected day and filter.
    final anyVisible = habits.any((h) {
      final custom = ref.watch(habitCustomizationProvider(h.uid)).valueOrNull ??
          const HabitCustomization();
      if (!custom.isScheduledForWeekday(selectedDate.weekday)) return false;
      final isDone = checked.contains(h.uid);
      if (filter == 'To Do' && isDone) return false;
      if (filter == 'Completed' && !isDone) return false;
      return true;
    });
    if (!anyVisible) {
      final cs = Theme.of(context).colorScheme;
      final message = switch (filter) {
        'To Do' => 'Everything is done for this day.',
        'Completed' => 'Nothing completed yet for this day.',
        _ => 'No habits scheduled for this day.',
      };
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            message,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

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
        if (!custom.isScheduledForWeekday(selectedDate.weekday)) continue;
        final isDone = checked.contains(h.uid);
        if (filter == 'To Do' && isDone) continue;
        if (filter == 'Completed' && !isDone) continue;
        matched.add(h);
      }
    }

    // Only time-of-day sections that actually hold habits are shown; an
    // empty "Night" or "Anytime" heading is just noise.
    if (matched.isEmpty) return const SizedBox.shrink();

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

          Column(
            children: [
              for (final habit in matched) ...[
                HabitRow(
                  habit: habit,
                  isDone: checked.contains(habit.uid),
                  onToggle: () => onToggle(habit.uid),
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

/// The Analytics view: every habit with how it is going. Tapping one opens
/// its month calendar.
class _HabitAnalyticsList extends ConsumerWidget {
  const _HabitAnalyticsList({required this.habits});

  final List<Habit> habits;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        for (final habit in habits) ...[
          _HabitAnalyticsRow(habit: habit),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _HabitAnalyticsRow extends ConsumerWidget {
  const _HabitAnalyticsRow({required this.habit});

  final Habit habit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final custom =
        ref.watch(habitCustomizationProvider(habit.uid)).valueOrNull ??
            const HabitCustomization();
    final done = ref.watch(habitCheckedDatesProvider(habit.uid)).valueOrNull ??
        const <DateTime>{};
    final stats = HabitStats.from(done, custom);
    final color = custom.color;

    return ItemSwipeActions(
      itemKey: ValueKey('analytics-${habit.uid}'),
      onEdit: () => HabitEditSheet.show(context, habit: habit),
      onDelete: () => deleteHabit(context, ref, habit),
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: cs.outline.withValues(alpha: 0.7)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          // In Analytics, opening a habit means opening its history.
          onTap: () => HabitHistorySheet.show(context, habit),
          onLongPress: () => showItemActions(context,
              title: habit.label, actions: habitActions(context, ref, habit)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(HabitIcons.resolve(habit.iconKey),
                      size: 20, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        habit.label.isEmpty ? 'Unnamed habit' : habit.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '🔥 ${stats.currentStreak} day streak · '
                        '${stats.thisMonth} this month',
                        style: tt.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.calendar_month_rounded,
                    size: 20, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
