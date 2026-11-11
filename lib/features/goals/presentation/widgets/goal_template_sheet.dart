import 'package:flutter/material.dart';

import '../../../../core/services/goal_template_service.dart';
import '../../../../core/layout/adaptive_sheet.dart';

Future<int?> showGoalTemplateSheet(BuildContext context) {
  return showAdaptiveSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _GoalTemplateSheet(),
  );
}

class _GoalTemplateSheet extends StatefulWidget {
  const _GoalTemplateSheet();

  @override
  State<_GoalTemplateSheet> createState() => _GoalTemplateSheetState();
}

class _GoalTemplateSheetState extends State<_GoalTemplateSheet> {
  // createFromTemplate performs a dozen writes; a second tap while it runs
  // would create the goal twice and skip the free-tier slot check.
  bool _busy = false;

  Future<void> _pick(GoalTemplate template) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final id = await GoalTemplateService.instance.createFromTemplate(
        template: template,
        colorHex: const Color(0xFF5B9CF6).value,
        targetDate: DateTime.now().add(const Duration(days: 90)),
      );
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create goal: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final templates = GoalTemplateService.instance.templates;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          const Text(
            'Use a goal template',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          ...templates.map(
            (template) => Card(
              child: ListTile(
                title: Text('${template.emoji} ${template.name}'),
                subtitle: Text(template.description),
                enabled: !_busy,
                onTap: () => _pick(template),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
