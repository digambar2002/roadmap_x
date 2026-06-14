import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/models/models.dart';
import '../../../core/models/today_task.dart';
import '../../../core/services/schedule_completion_service.dart';
import '../../tasks/data/task_repository.dart';
import '../../../shared/widgets/bottom_sheet_handle.dart';
import '../../../shared/widgets/confirmation_dialog.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../goals/providers/goal_provider.dart';
import '../data/schedule_repository.dart';
import '../providers/schedule_provider.dart';

class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final selectedDate = ref.watch(selectedScheduleDateProvider);
    final selectedDay = selectedDate.weekday % 7;
    final scheduleAsync = ref.watch(scheduleForWeekdayProvider(selectedDay));

    const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final today = todayDate.weekday % 7;
    final weekStart = todayDate.subtract(Duration(days: todayDate.weekday % 7));

    return Scaffold(
      backgroundColor: cs.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Text('Schedule',
                  style:
                      tt.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
            ).animate().fadeIn(duration: 300.ms),

            // ── Day selector ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _DaySelectorTabs(
                dayNames: dayNames,
                selectedDay: selectedDay,
                today: today,
                weekStart: weekStart,
                onSelect: (i) {
                  ref.read(selectedScheduleDateProvider.notifier).state = DateTime(
                        weekStart.year,
                        weekStart.month,
                        weekStart.day + i,
                      );
                },
              ),
            ).animate().fadeIn(delay: 80.ms),

            // ── Schedule items ───────────────────────────────
            Expanded(
              child: scheduleAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (items) => items.isEmpty
                    ? EmptyState(
                        emoji: '📅',
                        title: 'Nothing scheduled',
                        subtitle: 'Add a routine for ${dayNames[selectedDay]}.',
                        buttonLabel: '+ Add Item',
                        onButton: () => _openCreate(context),
                      )
                    : _ScheduleList(items: items, selectedDate: selectedDate),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'schedule_fab',
        onPressed: () => _openCreate(context),
        child: const Icon(Icons.add),
      ).animate().scale(delay: 200.ms),
    );
  }

  void _openCreate(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CreateEditScheduleSheet(),
    );
  }
}

class _DaySelectorTabs extends StatelessWidget {
  final List<String> dayNames;
  final int selectedDay;
  final int today;
  final DateTime weekStart;
  final ValueChanged<int> onSelect;

  const _DaySelectorTabs({
    required this.dayNames,
    required this.selectedDay,
    required this.today,
    required this.weekStart,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: cs.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline),
      ),
      child: Row(
        children: List.generate(7, (i) {
          final selected = selectedDay == i;
          final isToday = today == i;

          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < 6 ? 6 : 0),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onSelect(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? cs.primary
                        : isToday
                            ? cs.primary.withOpacity(0.12)
                            : cs.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? cs.primary
                          : isToday
                              ? cs.primary.withOpacity(0.35)
                              : cs.outline,
                    ),
                  ),
                  child: Text(
                    '${dayNames[i]}\n${weekStart.day + i}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : cs.onBackground,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Schedule list ─────────────────────────────────────────

class _ScheduleList extends StatelessWidget {
  final List<ScheduleItem> items;
  final DateTime selectedDate;
  const _ScheduleList({required this.items, required this.selectedDate});

  @override
  Widget build(BuildContext context) {
    // Sort by time
    final sorted = [...items]
      ..sort((a, b) => _parseTime(a.time).compareTo(_parseTime(b.time)));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: sorted.length,
      itemBuilder: (context, i) =>
          _ScheduleItemCard(item: sorted[i], selectedDate: selectedDate)
          .animate()
          .fadeIn(delay: (i * 40).ms)
          .slideY(begin: 0.05),
    );
  }

  int _parseTime(String time) {
    try {
      final parts = time.split(' ');
      final hm = parts[0].split(':');
      int h = int.parse(hm[0]);
      final m = int.parse(hm[1]);
      final ampm = parts[1].toUpperCase();
      if (ampm == 'PM' && h != 12) h += 12;
      if (ampm == 'AM' && h == 12) h = 0;
      return h * 60 + m;
    } catch (_) {
      return 0;
    }
  }
}

class _ScheduleItemCard extends ConsumerStatefulWidget {
  final ScheduleItem item;
  final DateTime selectedDate;
  const _ScheduleItemCard({
    required this.item,
    required this.selectedDate,
  });

  @override
  ConsumerState<_ScheduleItemCard> createState() => _ScheduleItemCardState();
}

class _ScheduleItemCardState extends ConsumerState<_ScheduleItemCard> {
  bool _expanded = false;
  List<TodayTaskContext> _linkedTasks = [];

  @override
  void initState() {
    super.initState();
    _loadLinkedTasks();
  }

  Future<void> _loadLinkedTasks() async {
    if (widget.item.goalUid.isEmpty) return;
    final tasks = await TaskRepository.instance
        .getNextTasksForGoal(widget.item.goalUid, limit: 3);
    if (mounted) setState(() => _linkedTasks = tasks);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final goalsAsync = ref.watch(allGoalsProvider);
    final completedAsync =
        ref.watch(scheduleCompletedUidsProvider(widget.selectedDate));
    Color accentColor = cs.primary;
    String? goalName;
    Goal? linkedGoal;

    if (widget.item.goalUid.isNotEmpty) {
      goalsAsync.whenData((goals) {
        try {
          final g = goals.firstWhere((g) => g.uid == widget.item.goalUid);
          accentColor = Color(g.colorHex);
          goalName = g.name;
          linkedGoal = g;
        } catch (_) {}
      });
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Slidable(
        key: ValueKey(widget.item.id),
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          children: [
            SlidableAction(
              onPressed: (_) => _delete(context),
              backgroundColor: cs.error,
              foregroundColor: Colors.white,
              icon: Icons.delete_outline,
              label: 'Delete',
              borderRadius: BorderRadius.circular(12),
            ),
          ],
        ),
        child: GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          onLongPress: () => _openEdit(context),
          child: Container(
            decoration: BoxDecoration(
              color: cs.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outline),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        bottomLeft: Radius.circular(12),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Checkbox(
                                value: completedAsync.valueOrNull
                                        ?.contains(widget.item.uid) ??
                                    false,
                                onChanged: (v) async {
                                  await ScheduleCompletionService.instance
                                      .setCompleted(
                                    widget.selectedDate,
                                    widget.item.uid,
                                    v ?? false,
                                  );
                                  ref.invalidate(scheduleCompletedUidsProvider(
                                      widget.selectedDate));
                                },
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: accentColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  widget.item.time,
                                  style: TextStyle(
                                    fontFamily: 'JetBrains Mono',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: accentColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  widget.item.label,
                                  style: tt.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              Icon(
                                _expanded
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 18,
                                color: cs.onSurfaceVariant,
                              ),
                            ],
                          ),
                          if (_expanded) ...[
                            const SizedBox(height: 8),
                            if (widget.item.detail.isNotEmpty)
                              Text(widget.item.detail, style: tt.bodySmall),
                            if (goalName != null) ...[
                              const SizedBox(height: 6),
                              GestureDetector(
                                onTap: linkedGoal == null
                                    ? null
                                    : () => context.push('/focus/${linkedGoal!.id}'),
                                child: Row(
                                children: [
                                  Icon(Icons.flag_outlined,
                                      size: 13, color: accentColor),
                                  const SizedBox(width: 6),
                                  Text(goalName!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: accentColor,
                                        fontWeight: FontWeight.w500,
                                      )),
                                  const Spacer(),
                                  if (linkedGoal != null)
                                    Text(
                                      'Focus →',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: accentColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                              ),
                            ],
                            if (_linkedTasks.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text('Next tasks',
                                  style: tt.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  )),
                              const SizedBox(height: 4),
                              ..._linkedTasks.map(
                                (ctx) => Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Text(
                                    '• ${ctx.task.text}',
                                    style: tt.bodySmall,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            _WeekdayChips(weekdays: widget.item.weekdays),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await ConfirmationDialog.show(
      context,
      title: 'Delete Schedule Item',
      message: 'Delete "${widget.item.label}"?',
    );
    if (ok) await ScheduleRepository.instance.delete(widget.item.id);
  }

  void _openEdit(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreateEditScheduleSheet(item: widget.item),
    );
  }
}

class _WeekdayChips extends StatelessWidget {
  final List<int> weekdays;
  const _WeekdayChips({required this.weekdays});

  @override
  Widget build(BuildContext context) {
    const names = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: List.generate(7, (i) {
        final active = weekdays.contains(i);
        return Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: active ? cs.primary.withOpacity(0.2) : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? cs.primary : cs.outline,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            names[i],
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: active ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
        );
      }),
    );
  }
}

// ── Create/Edit sheet ─────────────────────────────────────

class CreateEditScheduleSheet extends HookConsumerWidget {
  final ScheduleItem? item;
  const CreateEditScheduleSheet({super.key, this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isEdit = item != null;

    final labelCtrl = useTextEditingController(text: item?.label ?? '');
    final detailCtrl = useTextEditingController(text: item?.detail ?? '');
    final time = useState(item?.time ?? '7:00 AM');
    final selectedWeekdays =
        useState<Set<int>>(Set.from(item?.weekdays ?? [1, 2, 3, 4, 5]));
    final goalUid = useState(item?.goalUid ?? '');
    final isActive = useState(item?.isActive ?? true);
    final isSaving = useState(false);
    final formKey = useMemoized(GlobalKey<FormState>.new);

    final goalsAsync = ref.watch(allGoalsProvider);

    Future<void> save() async {
      if (!formKey.currentState!.validate()) return;
      isSaving.value = true;
      try {
        if (isEdit) {
          item!
            ..label = labelCtrl.text.trim()
            ..detail = detailCtrl.text.trim()
            ..time = time.value
            ..weekdays = selectedWeekdays.value.toList()
            ..goalUid = goalUid.value
            ..isActive = isActive.value;
          await ScheduleRepository.instance.update(item!);
        } else {
          await ScheduleRepository.instance.create(
            label: labelCtrl.text.trim(),
            detail: detailCtrl.text.trim(),
            time: time.value,
            weekdays: selectedWeekdays.value.toList(),
            goalUid: goalUid.value,
            isActive: isActive.value,
          );
        }
        if (context.mounted) Navigator.of(context).pop();
      } finally {
        isSaving.value = false;
      }
    }

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
          child: DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, ctrl) => ListView(
              controller: ctrl,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              children: [
                const BottomSheetHandle(),
                Text(
                  isEdit ? 'Edit Schedule Item' : 'New Schedule Item',
                  style:
                      tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 20),

                // Time picker
                _TimePickerField(
                  time: time.value,
                  onPicked: (t) => time.value = t,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Label *',
                    hintText: 'e.g. DSA Practice',
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Label required' : null,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: detailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Detail (optional)',
                    hintText: 'e.g. LeetCode medium problems',
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 20),

                // Goal link
                goalsAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (goals) => _GoalDropdown(
                    goals: goals,
                    selectedUid: goalUid.value,
                    onChanged: (uid) => goalUid.value = uid,
                  ),
                ),
                const SizedBox(height: 20),

                // Weekday selector
                Text('Repeat on',
                    style:
                        tt.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                _WeekdaySelector(
                  selected: selectedWeekdays.value,
                  onChanged: (days) => selectedWeekdays.value = days,
                ),
                const SizedBox(height: 16),

                // Active toggle
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: isActive.value,
                  onChanged: (v) => isActive.value = v,
                ),
                const SizedBox(height: 24),

                CustomButton(
                  label: isEdit ? 'Save Changes' : 'Add to Schedule',
                  isLoading: isSaving.value,
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

class _TimePickerField extends StatelessWidget {
  final String time;
  final ValueChanged<String> onPicked;

  const _TimePickerField({required this.time, required this.onPicked});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: () async {
        final parts = time.split(' ');
        final hm = parts[0].split(':');
        int h = int.parse(hm[0]);
        final m = int.parse(hm[1]);
        if (parts[1].toUpperCase() == 'PM' && h != 12) h += 12;
        if (parts[1].toUpperCase() == 'AM' && h == 12) h = 0;

        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: h, minute: m),
        );
        if (picked != null) {
          final hour12 = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
          final minute = picked.minute.toString().padLeft(2, '0');
          final period = picked.period == DayPeriod.am ? 'AM' : 'PM';
          final formatted = '$hour12:$minute $period';
          onPicked(formatted);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outline),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Time',
                      style:
                          tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  Text(
                    time,
                    style: tt.bodyLarge?.copyWith(
                      fontFamily: 'JetBrains Mono',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _GoalDropdown extends StatelessWidget {
  final List<Goal> goals;
  final String selectedUid;
  final ValueChanged<String> onChanged;

  const _GoalDropdown({
    required this.goals,
    required this.selectedUid,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Linked Goal (optional)',
            style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: selectedUid.isEmpty ? '' : selectedUid,
          decoration: InputDecoration(
            filled: true,
            fillColor: cs.surface,
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('No goal')),
            ...goals.map((g) => DropdownMenuItem(
                  value: g.uid,
                  child: Row(
                    children: [
                      Text(g.emoji, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Text(g.name),
                    ],
                  ),
                )),
          ],
          onChanged: (v) => onChanged(v ?? ''),
        ),
      ],
    );
  }
}

class _WeekdaySelector extends StatelessWidget {
  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;

  const _WeekdaySelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const labels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: List.generate(7, (i) {
        final active = selected.contains(i);
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < 6 ? 4 : 0),
            child: GestureDetector(
              onTap: () {
                final newSet = Set<int>.from(selected);
                if (active) {
                  newSet.remove(i);
                } else {
                  newSet.add(i);
                }
                onChanged(newSet);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 36,
                decoration: BoxDecoration(
                  color:
                      active ? cs.primary.withOpacity(0.2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: active ? cs.primary : cs.outline,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  labels[i].substring(0, 1),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: active ? cs.primary : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
