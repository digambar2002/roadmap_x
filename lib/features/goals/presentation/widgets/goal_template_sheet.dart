import 'package:flutter/material.dart';

import '../../../../core/services/goal_template_service.dart';

Future<int?> showGoalTemplateSheet(BuildContext context) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _GoalTemplateSheet(),
  );
}

class _GoalTemplateSheet extends StatelessWidget {
  const _GoalTemplateSheet();

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
                onTap: () async {
                  final id = await GoalTemplateService.instance.createFromTemplate(
                    template: template,
                    colorHex: const Color(0xFF5B9CF6).value,
                    targetDate: DateTime.now().add(const Duration(days: 90)),
                  );
                  if (context.mounted) Navigator.pop(context, id);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
