import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/layout/adaptive_page.dart';
import '../../../core/layout/adaptive_sheet.dart';
import '../../../core/layout/breakpoints.dart';
import '../../ai_goal/presentation/ai_goal_sheet.dart';
import '../../ai_goal/presentation/ai_plan_allowance_text.dart';
import '../../ai_goal/presentation/paste_plan_sheet.dart';
import '../../ai_goal/providers/ai_goal_provider.dart';
import '../../goals/presentation/widgets/goal_template_sheet.dart';
import '../../goals/providers/goal_provider.dart';
import '../../pet/presentation/pet_screen.dart';
import '../../pet/providers/pet_provider.dart';
import '../../premium/presentation/premium_gate.dart';

/// The last step of onboarding: leave with a real plan, not an empty app.
///
/// The user says what they want in a sentence and AI builds the milestones
/// and tasks. Pasting a plan they already have, or starting from a
/// template, work without an account. Then they pick a companion, so the
/// reward loop is running from the first day.
class FirstGoalScreen extends ConsumerStatefulWidget {
  const FirstGoalScreen({super.key});

  @override
  ConsumerState<FirstGoalScreen> createState() => _FirstGoalScreenState();
}

class _FirstGoalScreenState extends ConsumerState<FirstGoalScreen> {
  final _text = TextEditingController();
  String? _error;

  /// True once the user starts creating something here, so goals arriving
  /// from their own action don't trigger the "you already have goals" exit.
  bool _creating = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/today');
    }
  }

  Future<void> _buildWithAi() async {
    final prompt = _text.text.trim();
    if (prompt.length < 10) {
      setState(() => _error = 'Add a little more detail, like "in 3 months".');
      return;
    }
    setState(() => _error = null);
    FocusScope.of(context).unfocus();
    // Signed out, this offers a free sign-in and returns false; the text
    // stays here for when they come back.
    if (!await PremiumGate.ensureAi(context, ref)) return;
    if (!mounted) return;
    _creating = true;
    final generator = ref.read(aiGoalGeneratorProvider.notifier);
    generator.setPrompt(prompt);
    // Start now, so the sheet opens straight onto "building your plan"
    // instead of asking for the same sentence again.
    generator.generate();
    final goalId = await showAiGoalSheet(context);
    await _finish(goalId);
  }

  Future<void> _paste() async {
    _creating = true;
    final goalId = await showPastePlanSheet(context);
    await _finish(goalId);
  }

  Future<void> _template() async {
    _creating = true;
    final goalId = await showGoalTemplateSheet(context);
    await _finish(goalId);
  }

  Future<void> _finish(int? goalId) async {
    if (!mounted) return;
    if (goalId == null) {
      _creating = false;
      return;
    }
    if (ref.read(petViewProvider) == null) {
      await showAdaptiveSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const AdoptView(popWhenAdopted: true),
      );
      if (!mounted) return;
    }
    context.go('/goals/$goalId');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // Signing in to an existing account during onboarding brings its goals
    // down. Someone who already has a plan doesn't need this page.
    ref.listen(allGoalsProvider, (_, next) {
      final goals = next.valueOrNull;
      if (!_creating && goals != null && goals.isNotEmpty && mounted) {
        _leave();
      }
    });

    return Scaffold(
      backgroundColor: cs.surface,
      body: AdaptivePage(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
                context.pageGutter, 4, context.pageGutter, 24),
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _leave,
                  child: const Text('Skip'),
                ),
              ),
              const Text('🎯', style: TextStyle(fontSize: 44)),
              const SizedBox(height: 12),
              Text(
                'What do you want to achieve?',
                style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Say it in a sentence. AI turns it into milestones and tasks '
                'you can start on today.',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _text,
                minLines: 3,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'e.g. I want to run my first 5K in 8 weeks, '
                      'starting from zero',
                  border: const OutlineInputBorder(),
                  errorText: _error,
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in aiGoalSuggestions.entries)
                    ActionChip(
                      label: Text(entry.key),
                      onPressed: () => setState(() {
                        _text.text = entry.value;
                        _error = null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _buildWithAi,
                icon: const Icon(Icons.auto_awesome, size: 20),
                label: const Text('Build my plan'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 6),
              AiPlanAllowanceText(
                textAlign: TextAlign.center,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: Divider(color: cs.outlineVariant)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'or',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                  Expanded(child: Divider(color: cs.outlineVariant)),
                ],
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _paste,
                icon: const Icon(Icons.content_paste_rounded, size: 20),
                label: const Text('Paste a plan I already have'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'From ChatGPT, your notes, anywhere. Works without an account.',
                textAlign: TextAlign.center,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _template,
                icon: const Icon(Icons.library_books_outlined, size: 20),
                label: const Text('Start from a template'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
