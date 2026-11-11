import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/ai/gemini_provider.dart';
import '../../../core/ai/gemini_service.dart';
import '../../../core/layout/adaptive_sheet.dart';
import '../../premium/presentation/premium_gate.dart';
import '../data/goal_plan_saver.dart';
import '../data/plan_text_parser.dart';

/// Opens the "Create from text" sheet. Returns the new goal's id, or null.
Future<int?> showPastePlanSheet(BuildContext context) => showAdaptiveSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const PastePlanSheet(),
    );

/// Paste a plan, a list or notes and get a goal with milestones and tasks.
///
/// The free parser runs on the device and handles ordinary lists and
/// headings. "Organise with AI" is there for messier text such as an email
/// or meeting notes. Either way the result is shown for review before
/// anything is created.
class PastePlanSheet extends ConsumerStatefulWidget {
  const PastePlanSheet({super.key});

  @override
  ConsumerState<PastePlanSheet> createState() => _PastePlanSheetState();
}

class _PastePlanSheetState extends ConsumerState<PastePlanSheet> {
  final _text = TextEditingController();
  final _name = TextEditingController();
  AiGoalResponse? _plan;
  String? _error;
  bool _busy = false;

  static const _example = 'Learn Spanish\n'
      'Week 1: Basics\n'
      '- Learn 100 common words\n'
      '- Practise greetings\n'
      'Week 2: Grammar\n'
      '- Present tense verbs\n'
      '- Watch a film in Spanish';

  @override
  void dispose() {
    _text.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.trim().isEmpty) {
      setState(() => _error = 'The clipboard is empty.');
      return;
    }
    _text.text = text;
    _text.selection = TextSelection.collapsed(offset: text.length);
    setState(() => _error = null);
  }

  void _showPlan(AiGoalResponse plan) {
    if (plan.totalTasks == 0) {
      setState(() => _error =
          'No tasks found. Put each task on its own line (bullets or numbers '
              'work), or try Organise with AI.');
      return;
    }
    _name.text = plan.goal.name;
    setState(() {
      _plan = plan;
      _error = null;
    });
  }

  void _preview() {
    final text = _text.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Paste or type your plan first.');
      return;
    }
    _showPlan(PlanTextParser.parse(text));
  }

  Future<void> _organiseWithAi() async {
    final text = _text.text.trim();
    if (text.length < 10) {
      setState(() => _error = 'Paste a bit more text for the AI to work with.');
      return;
    }
    if (!await PremiumGate.ensureAi(context, ref)) return;
    final service = ref.read(geminiServiceProvider);
    if (service == null) {
      setState(() =>
          _error = 'Add a Gemini API key in Settings → AI coach to use this.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final plan = await service.structurePlan(text);
      if (mounted) _showPlan(plan);
    } on GeminiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final plan = _plan;
    if (plan == null) return;
    setState(() => _busy = true);
    try {
      final id = await saveGoalPlan(plan, goalName: _name.text);
      if (mounted) Navigator.of(context).pop(id);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not create the goal. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final plan = _plan;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  plan == null ? 'Create from text' : 'Review your goal',
                  style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  plan == null
                      ? 'Paste a plan, a list or notes. Headings and lines '
                          'like "Week 1:" become milestones; bullets and '
                          'numbered lines become tasks.'
                      : '${plan.milestones.length} milestone'
                          '${plan.milestones.length == 1 ? '' : 's'} · '
                          '${plan.totalTasks} task'
                          '${plan.totalTasks == 1 ? '' : 's'}',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                if (plan == null)
                  ..._inputView(cs, tt)
                else
                  ..._previewView(plan, cs, tt),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: tt.bodySmall?.copyWith(color: cs.error)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _inputView(ColorScheme cs, TextTheme tt) => [
        TextField(
          controller: _text,
          minLines: 8,
          maxLines: 14,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            hintText: _example,
            hintMaxLines: 8,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton.icon(
              onPressed: _busy ? null : _paste,
              icon: const Icon(Icons.content_paste_rounded, size: 18),
              label: const Text('Paste'),
            ),
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () {
                      _text.clear();
                      setState(() => _error = null);
                    },
              icon: const Icon(Icons.clear_rounded, size: 18),
              label: const Text('Clear'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy ? null : _preview,
          icon: const Icon(Icons.visibility_outlined, size: 18),
          label: const Text('Preview'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _organiseWithAi,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome, size: 18),
          label: Text(_busy ? 'Organising…' : 'Organise with AI'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Preview is free and works offline. AI is for messy text like '
          'emails or meeting notes.',
          textAlign: TextAlign.center,
          style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ];

  List<Widget> _previewView(
          AiGoalResponse plan, ColorScheme cs, TextTheme tt) =>
      [
        TextField(
          controller: _name,
          maxLength: 60,
          decoration: InputDecoration(
            labelText: 'Goal name',
            prefixText: '${plan.goal.emoji}  ',
            border: const OutlineInputBorder(),
          ),
        ),
        if (plan.goal.description.isNotEmpty) ...[
          Text(plan.goal.description, style: tt.bodySmall),
          const SizedBox(height: 10),
        ],
        for (final m in plan.milestones) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: m.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (m.theme.isNotEmpty)
                      TextSpan(
                        text: '  ${m.theme}',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                  ]),
                ),
                const SizedBox(height: 6),
                for (final t in m.tasks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: switch (t.priority) {
                                2 => const Color(0xFFF87171),
                                1 => const Color(0xFFFBBF24),
                                _ => cs.outline,
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(t.text, style: tt.bodySmall)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : () => setState(() => _plan = null),
                child: const Text('Edit text'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: _busy ? null : _create,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create goal'),
              ),
            ),
          ],
        ),
      ];
}
