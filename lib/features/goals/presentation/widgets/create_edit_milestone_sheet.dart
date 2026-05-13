import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../../core/models/models.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../shared/widgets/bottom_sheet_handle.dart';
import '../../../../shared/widgets/custom_button.dart';
import '../../../milestones/data/milestone_repository.dart';

class CreateEditMilestoneSheet extends HookConsumerWidget {
  final int goalId;
  final Milestone? milestone;

  const CreateEditMilestoneSheet({
    super.key,
    required this.goalId,
    this.milestone,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isEdit = milestone != null;

    final titleCtrl = useTextEditingController(text: milestone?.title ?? '');
    final themeCtrl = useTextEditingController(text: milestone?.theme ?? '');
    final dueDate = useState<DateTime?>(milestone?.dueDate);
    final isSaving = useState(false);
    final formKey = useMemoized(GlobalKey<FormState>.new);

    Future<void> save() async {
      if (!formKey.currentState!.validate()) return;
      isSaving.value = true;
      try {
        if (isEdit) {
          milestone!
            ..title = titleCtrl.text.trim()
            ..theme = themeCtrl.text.trim()
            ..dueDate = dueDate.value;
          await MilestoneRepository.instance.update(milestone!);
        } else {
          await MilestoneRepository.instance.create(
            goalId: goalId,
            title: titleCtrl.text.trim(),
            theme: themeCtrl.text.trim(),
            dueDate: dueDate.value,
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BottomSheetHandle(),
                Text(
                  isEdit ? 'Edit Milestone' : 'New Milestone',
                  style:
                      tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Title *',
                    hintText: 'e.g. Month 1, Phase 1, Week 1–2',
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Title required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: themeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Theme / Description (optional)',
                    hintText: 'e.g. Foundation & basics',
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 16),
                _OptionalDateField(
                  label: 'Due Date (optional)',
                  date: dueDate.value,
                  onPicked: (d) => dueDate.value = d,
                  onClear: () => dueDate.value = null,
                ),
                const SizedBox(height: 28),
                CustomButton(
                  label: isEdit ? 'Save Changes' : 'Add Milestone',
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

class _OptionalDateField extends StatelessWidget {
  final String label;
  final DateTime? date;
  final ValueChanged<DateTime> onPicked;
  final VoidCallback onClear;

  const _OptionalDateField({
    required this.label,
    required this.date,
    required this.onPicked,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now().add(const Duration(days: 30)),
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
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
              child: Text(
                date != null ? AppDateUtils.formatDate(date!) : label,
                style: date != null
                    ? tt.bodyMedium
                    : tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            if (date != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}
