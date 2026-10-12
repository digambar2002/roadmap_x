import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/layout/adaptive_sheet.dart';
import '../../../../core/models/habit_icons.dart';
import '../../../../core/models/models.dart';
import '../../../../core/services/habit_customization_service.dart';
import '../../../../shared/widgets/bottom_sheet_handle.dart';
import '../../../../shared/widgets/confirmation_dialog.dart';
import '../../data/habit_repository.dart';
import '../../providers/habit_provider.dart';

/// Full-featured customization sheet for creating or editing a Habit.
///
/// Supports:
/// - Title & Icon
/// - Custom Accent Color
/// - Repeat Frequency (Everyday, Weekdays, Weekends, Custom days)
/// - Category (Morning, Workload, Night, Anytime)
/// - Scheduled Notification Reminder
class HabitEditSheet extends ConsumerStatefulWidget {
  const HabitEditSheet({
    super.key,
    this.habit,
    this.initialCategory,
  });

  final Habit? habit;
  final String? initialCategory;

  static Future<void> show(
    BuildContext context, {
    Habit? habit,
    String? initialCategory,
  }) {
    return showAdaptiveSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => HabitEditSheet(
        habit: habit,
        initialCategory: initialCategory,
      ),
    );
  }

  @override
  ConsumerState<HabitEditSheet> createState() => _HabitEditSheetState();
}

class _HabitEditSheetState extends ConsumerState<HabitEditSheet> {
  late final TextEditingController _nameController;
  late String _selectedIcon;
  late int _selectedColor;
  late String _selectedCategory;
  late List<int> _selectedDays;
  late bool _hasReminder;
  late int _reminderHour;
  late int _reminderMinute;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.habit?.label ?? '');
    _selectedIcon = widget.habit?.iconKey ?? HabitIcons.fallbackKey;
    _selectedColor = 0xFF10B981;
    _selectedCategory = widget.initialCategory ?? 'Morning';
    _selectedDays = [1, 2, 3, 4, 5, 6, 7];
    _hasReminder = false;
    _reminderHour = 8;
    _reminderMinute = 0;

    _loadExistingCustomization();
  }

  Future<void> _loadExistingCustomization() async {
    if (widget.habit != null) {
      final custom = await HabitCustomizationService.instance.get(widget.habit!.uid);
      if (mounted) {
        setState(() {
          _selectedColor = custom.colorHex;
          _selectedCategory = custom.category;
          _selectedDays = List<int>.from(custom.repeatDays);
          _hasReminder = custom.hasReminder;
          _reminderHour = custom.reminderHour;
          _reminderMinute = custom.reminderMinute;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _reminderHour, minute: _reminderMinute),
    );
    if (picked != null && mounted) {
      setState(() {
        _reminderHour = picked.hour;
        _reminderMinute = picked.minute;
        _hasReminder = true;
      });
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a habit name')),
      );
      return;
    }

    Habit targetHabit;
    if (widget.habit == null) {
      targetHabit = await HabitRepository.instance.create(
        label: name,
        iconKey: _selectedIcon,
      );
    } else {
      targetHabit = widget.habit!;
      targetHabit.label = name;
      targetHabit.iconKey = _selectedIcon;
      await HabitRepository.instance.update(targetHabit);
    }

    final custom = HabitCustomization(
      colorHex: _selectedColor,
      repeatDays: _selectedDays,
      category: _selectedCategory,
      hasReminder: _hasReminder,
      reminderHour: _reminderHour,
      reminderMinute: _reminderMinute,
    );

    await HabitCustomizationService.instance.save(
      targetHabit.uid,
      custom,
      habitLabel: name,
    );

    ref.read(habitCustomizationVersionProvider.notifier).state++;
    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _delete() async {
    if (widget.habit == null) return;
    final confirmed = await ConfirmationDialog.show(
      context,
      title: 'Remove Habit?',
      message: 'Remove "${widget.habit!.label}" from your habits?',
      confirmLabel: 'Remove',
    );
    if (!confirmed || !mounted) return;

    await HabitRepository.instance.delete(widget.habit!.id);
    await HabitCustomizationService.instance.delete(widget.habit!.uid);
    ref.read(habitCustomizationVersionProvider.notifier).state++;
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (_isLoading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final isEditing = widget.habit != null;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const BottomSheetHandle(),
              const SizedBox(height: 8),

              // ── Header ───────────────────────────────────────────
              Row(
                children: [
                  Text(
                    isEditing ? 'Customize Habit' : 'New Habit',
                    style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  if (isEditing)
                    IconButton(
                      icon: Icon(Icons.delete_outline_rounded, color: cs.error),
                      tooltip: 'Delete habit',
                      onPressed: _delete,
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Habit Name & Icon Input ──────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Icon button
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      final key = await pickHabitIcon(context, selected: _selectedIcon);
                      if (key != null && mounted) {
                        setState(() => _selectedIcon = key);
                      }
                    },
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Color(_selectedColor).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Color(_selectedColor), width: 1.5),
                      ),
                      child: Icon(
                        HabitIcons.resolve(_selectedIcon),
                        color: Color(_selectedColor),
                        size: 26,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Name Field
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      autofocus: !isEditing,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'e.g. Read 20 mins, Gym, Drink water',
                        labelText: 'Habit Name',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Color Picker ──────────────────────────────────────
              Text(
                'COLOR ACCENT',
                style: tt.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: HabitCustomization.presetColors.map((colorVal) {
                  final isSelected = _selectedColor == colorVal;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = colorVal),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Color(colorVal),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.transparent,
                          width: 2.5,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: Color(colorVal).withValues(alpha: 0.4),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                )
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // ── Category / Time of Day ────────────────────────────
              Text(
                'TIME OF DAY / CATEGORY',
                style: tt.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: HabitCustomization.presetCategories.map((cat) {
                  final isSelected = _selectedCategory == cat;
                  return ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    onSelected: (val) {
                      if (val) setState(() => _selectedCategory = cat);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // ── Repeat Frequency ──────────────────────────────────
              Text(
                'REPEAT DAYS',
                style: tt.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),

              // Quick Presets: Everyday, Weekdays, Weekends
              Row(
                children: [
                  _PresetChip(
                    label: 'Everyday',
                    isSelected: _selectedDays.length == 7,
                    color: Color(_selectedColor),
                    onTap: () => setState(() => _selectedDays = [1, 2, 3, 4, 5, 6, 7]),
                  ),
                  const SizedBox(width: 8),
                  _PresetChip(
                    label: 'Weekdays',
                    isSelected: _selectedDays.length == 5 &&
                        _selectedDays.every((d) => d <= 5),
                    color: Color(_selectedColor),
                    onTap: () => setState(() => _selectedDays = [1, 2, 3, 4, 5]),
                  ),
                  const SizedBox(width: 8),
                  _PresetChip(
                    label: 'Weekends',
                    isSelected: _selectedDays.length == 2 &&
                        _selectedDays.contains(6) &&
                        _selectedDays.contains(7),
                    color: Color(_selectedColor),
                    onTap: () => setState(() => _selectedDays = [6, 7]),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Responsive 7-Day Expanded Row
              Row(
                children: [
                  for (final entry in [
                    (1, 'Mon'),
                    (2, 'Tue'),
                    (3, 'Wed'),
                    (4, 'Thu'),
                    (5, 'Fri'),
                    (6, 'Sat'),
                    (7, 'Sun')
                  ]) ...[
                    Expanded(
                      child: _DayPill(
                        dayName: entry.$2,
                        isSelected: _selectedDays.contains(entry.$1),
                        accentColor: Color(_selectedColor),
                        onTap: () {
                          setState(() {
                            if (_selectedDays.contains(entry.$1)) {
                              if (_selectedDays.length > 1) {
                                _selectedDays.remove(entry.$1);
                              }
                            } else {
                              _selectedDays.add(entry.$1);
                              _selectedDays.sort();
                            }
                          });
                        },
                      ),
                    ),
                    if (entry.$1 != 7) const SizedBox(width: 5),
                  ],
                ],
              ),
              const SizedBox(height: 20),

              // ── Notification Reminder ─────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.outline),
                ),
                child: Row(
                  children: [
                    Icon(
                      _hasReminder
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_none_rounded,
                      color: _hasReminder ? Color(_selectedColor) : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Daily Reminder',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            _hasReminder
                                ? 'Alert at ${_formatTime(_reminderHour, _reminderMinute)}'
                                : 'No alert set',
                            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (_hasReminder)
                      TextButton(
                        onPressed: _pickTime,
                        child: Text(
                          _formatTime(_reminderHour, _reminderMinute),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(_selectedColor),
                          ),
                        ),
                      ),
                    Switch(
                      value: _hasReminder,
                      activeColor: Color(_selectedColor),
                      onChanged: (val) {
                        setState(() => _hasReminder = val);
                        if (val) _pickTime();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Save Button ───────────────────────────────────────
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(_selectedColor),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _save,
                child: Text(
                  isEditing ? 'Save Changes' : 'Create Habit',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(int hour, int minute) {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final m = minute.toString().padLeft(2, '0');
    final p = hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $p';
  }
}

/// Grid of the available habit icons. Returns null if dismissed.
Future<String?> pickHabitIcon(
  BuildContext context, {
  required String selected,
}) {
  return showAdaptiveSheet<String>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (sheetContext) {
      final cs = Theme.of(sheetContext).colorScheme;
      final tt = Theme.of(sheetContext).textTheme;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BottomSheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'Pick an icon',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Flexible(
              child: GridView.count(
                shrinkWrap: true,
                crossAxisCount: 6,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  for (final key in HabitIcons.keys)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.pop(sheetContext, key),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: key == selected ? cs.primary : cs.outline,
                            width: key == selected ? 2 : 1,
                          ),
                          color: key == selected
                              ? cs.primary.withValues(alpha: 0.12)
                              : Colors.transparent,
                        ),
                        child: Icon(
                          HabitIcons.catalog[key],
                          color:
                              key == selected ? cs.primary : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final Color color;
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
              ? color.withValues(alpha: 0.18)
              : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : cs.outline.withValues(alpha: 0.7),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? color : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _DayPill extends StatelessWidget {
  const _DayPill({
    required this.dayName,
    required this.isSelected,
    required this.accentColor,
    required this.onTap,
  });

  final String dayName;
  final bool isSelected;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? accentColor : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? accentColor : cs.outline.withValues(alpha: 0.5),
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Text(
          dayName,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}


