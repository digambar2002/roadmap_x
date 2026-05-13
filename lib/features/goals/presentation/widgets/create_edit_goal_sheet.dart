import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../../../../core/models/models.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../shared/widgets/bottom_sheet_handle.dart';
import '../../../../shared/widgets/color_picker.dart';
import '../../../../shared/widgets/custom_button.dart';
import '../../../../shared/widgets/icon_picker.dart';
import '../../data/goal_repository.dart';

class CreateEditGoalSheet extends HookConsumerWidget {
  final Goal? goal; // null = create mode

  const CreateEditGoalSheet({super.key, this.goal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isEdit = goal != null;

    // Form state
    final nameCtrl = useTextEditingController(text: goal?.name ?? '');
    final descCtrl = useTextEditingController(text: goal?.description ?? '');
    final emoji = useState(goal?.emoji ?? '🎯');
    final colorHex = useState(goal?.colorHex ?? AppColors.goalColorHexes.first);
    final targetDate = useState(
        goal?.targetDate ?? DateTime.now().add(const Duration(days: 90)));
    final isSaving = useState(false);
    final formKey = useMemoized(GlobalKey<FormState>.new);

    Future<void> save() async {
      if (!formKey.currentState!.validate()) return;
      isSaving.value = true;
      try {
        if (isEdit) {
          goal!
            ..name = nameCtrl.text.trim()
            ..description = descCtrl.text.trim()
            ..emoji = emoji.value
            ..colorHex = colorHex.value
            ..targetDate = targetDate.value;
          await GoalRepository.instance.update(goal!);
        } else {
          await GoalRepository.instance.create(
            name: nameCtrl.text.trim(),
            description: descCtrl.text.trim(),
            emoji: emoji.value,
            colorHex: colorHex.value,
            targetDate: targetDate.value,
          );
        }
        if (context.mounted) Navigator.of(context).pop();
      } finally {
        isSaving.value = false;
      }
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Form(
          key: formKey,
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            children: [
              const BottomSheetHandle(),
              Text(
                isEdit ? 'Edit Goal' : 'New Goal',
                style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 24),

              // ── Emoji ──────────────────────────────────────
              _Section(
                label: 'Choose Emoji',
                child: EmojiPickerWidget(
                  selectedEmoji: emoji.value,
                  onSelected: (e) => emoji.value = e,
                ),
              ),
              const SizedBox(height: 20),

              // ── Name ──────────────────────────────────────
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Goal Name *',
                  hintText: 'e.g. Learn Flutter',
                ),
                textCapitalization: TextCapitalization.sentences,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),

              // ── Description ───────────────────────────────
              TextFormField(
                controller: descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'What do you want to achieve?',
                ),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 20),

              // ── Color ─────────────────────────────────────
              _Section(
                label: 'Pick a Color',
                child: GoalColorPicker(
                  selectedHex: colorHex.value,
                  onSelected: (h) => colorHex.value = h,
                ),
              ),
              const SizedBox(height: 20),

              // ── Target date ───────────────────────────────
              _DatePickerField(
                label: 'Target Date',
                date: targetDate.value,
                onPicked: (d) => targetDate.value = d,
              ),
              const SizedBox(height: 32),

              // ── Save ──────────────────────────────────────
              CustomButton(
                label: isEdit ? 'Save Changes' : 'Create Goal',
                isLoading: isSaving.value,
                onPressed: save,
                color: Color(colorHex.value),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String label;
  final Widget child;
  const _Section({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _DatePickerField extends StatelessWidget {
  final String label;
  final DateTime date;
  final ValueChanged<DateTime> onPicked;

  const _DatePickerField({
    required this.label,
    required this.date,
    required this.onPicked,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 3650)),
        );
        if (picked != null) onPicked(picked);
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
            Icon(Icons.calendar_today_outlined,
                size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style:
                          tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text(AppDateUtils.formatDate(date), style: tt.bodyMedium),
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
