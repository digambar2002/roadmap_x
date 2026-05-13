import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/ai/gemini_service.dart';
import '../../settings/providers/ai_settings_provider.dart';
import '../providers/ai_goal_provider.dart';

Future<int?> showAiGoalSheet(BuildContext context) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => const AiGoalSheet(),
  );
}

class AiGoalSheet extends ConsumerStatefulWidget {
  const AiGoalSheet({super.key});

  @override
  ConsumerState<AiGoalSheet> createState() => _AiGoalSheetState();
}

class _AiGoalSheetState extends ConsumerState<AiGoalSheet> {
  static const _gradient = LinearGradient(
    colors: [Color(0xFF5B9CF6), Color(0xFFA78BFA)],
  );

  static const _suggestions = <String, String>{
    'Learn DSA':
        'I want to learn Data Structures and Algorithms step by step for placement interviews in 3 months',
    'Master Flutter':
        'I want to master Flutter app development from basics to advanced in 2 months',
    'Crack FAANG':
        'I want to prepare for FAANG software engineering interviews in 6 months',
    'Build SaaS':
        'I want to build and launch a SaaS product from idea to first 10 customers in 3 months',
    'Get fit':
        'I want to get fit and build a consistent workout habit over the next 12 weeks',
  };

  static const _loadingMessages = <String>[
    'Thinking about your milestones...',
    'Breaking it down into tasks...',
    'Organizing your learning path...',
    'Almost there...',
  ];

  final _promptController = TextEditingController();
  final _expandedMilestones = <int>{};
  Timer? _timer;
  int _loadingIndex = 0;

  @override
  void initState() {
    super.initState();
    final state = ref.read(aiGoalGeneratorProvider);
    _promptController.text = state.prompt;
    _promptController.addListener(() {
      ref.read(aiGoalGeneratorProvider.notifier).setPrompt(_promptController.text);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _promptController.dispose();
    super.dispose();
  }

  void _startLoadingTicker() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      setState(() {
        _loadingIndex = (_loadingIndex + 1) % _loadingMessages.length;
      });
    });
  }

  void _stopLoadingTicker() {
    _timer?.cancel();
    _timer = null;
    if (_loadingIndex != 0) {
      setState(() => _loadingIndex = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(aiGoalGeneratorProvider, (previous, next) {
      if (next.status == AiGenerationStatus.loading) {
        if (_timer == null) _startLoadingTicker();
      } else {
        _stopLoadingTicker();
      }
    });

    final cs = Theme.of(context).colorScheme;
    final state = ref.watch(aiGoalGeneratorProvider);
    final notifier = ref.read(aiGoalGeneratorProvider.notifier);
    final hasKey = ref.watch(aiSettingsRepositoryProvider).hasApiKey;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          children: [
            _Header(
              onClose: () => Navigator.of(context).pop(),
              gradient: _gradient,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: cs.outline),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: !hasKey
                      ? _NoApiKeyView(
                          onGoToSettings: () {
                            Navigator.of(context).pop();
                            context.push('/settings');
                          },
                        )
                      : switch (state.status) {
                          AiGenerationStatus.loading => _LoadingView(
                              gradient: _gradient,
                              subtitle: _loadingMessages[_loadingIndex],
                            ),
                          AiGenerationStatus.success => _PreviewView(
                              response: state.result!,
                              expandedMilestones: _expandedMilestones,
                              onToggleMilestone: (index) {
                                setState(() {
                                  if (_expandedMilestones.contains(index)) {
                                    _expandedMilestones.remove(index);
                                  } else {
                                    _expandedMilestones.add(index);
                                  }
                                });
                              },
                              onEditPrompt: () {
                                notifier.toInput();
                                _stopLoadingTicker();
                                _promptController.text = state.prompt;
                                _promptController.selection = TextSelection.collapsed(
                                  offset: _promptController.text.length,
                                );
                              },
                              onTryAgain: notifier.generate,
                              onSave: () async {
                                final navigator = Navigator.of(context);
                                final messenger = ScaffoldMessenger.of(context);
                                final goalId = await notifier.saveToDatabase();

                                if (goalId == null) {
                                  final err = ref.read(aiGoalGeneratorProvider).errorMessage ??
                                      'Failed to save goal.';
                                  messenger.showSnackBar(
                                    SnackBar(content: Text(err)),
                                  );
                                  return;
                                }

                                navigator.pop(goalId);
                              },
                            ),
                          _ => _PromptInputView(
                              controller: _promptController,
                              errorMessage: state.errorMessage,
                              technicalDetails: state.technicalDetails,
                              onPickSuggestion: (label) {
                                final prompt = _suggestions[label]!;
                                _promptController.text = prompt;
                                _promptController.selection = TextSelection.collapsed(
                                  offset: prompt.length,
                                );
                              },
                              onGenerate: notifier.generate,
                              gradient: _gradient,
                            ),
                        },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onClose,
    required this.gradient,
  });

  final VoidCallback onClose;
  final LinearGradient gradient;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ShaderMask(
          shaderCallback: gradient.createShader,
          child: const Icon(Icons.auto_awesome, color: Colors.white),
        ),
        const SizedBox(width: 8),
        ShaderMask(
          shaderCallback: gradient.createShader,
          child: Text(
            'AI Goal Generator',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}

class _NoApiKeyView extends StatelessWidget {
  const _NoApiKeyView({required this.onGoToSettings});

  final VoidCallback onGoToSettings;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🔑', style: TextStyle(fontSize: 38)),
          const SizedBox(height: 12),
          Text(
            'Set up your API Key first',
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Add your free Gemini API key in Settings to enable AI-powered goal generation.',
            style: tt.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onGoToSettings,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Go to Settings -> AI Configuration'),
          ),
        ],
      ),
    );
  }
}

class _PromptInputView extends ConsumerWidget {
  const _PromptInputView({
    required this.controller,
    required this.errorMessage,
    required this.technicalDetails,
    required this.onPickSuggestion,
    required this.onGenerate,
    required this.gradient,
  });

  final TextEditingController controller;
  final String? errorMessage;
  final String? technicalDetails;
  final ValueChanged<String> onPickSuggestion;
  final VoidCallback onGenerate;
  final LinearGradient gradient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final prompt = ref.watch(aiGoalGeneratorProvider).prompt;
    final trimmed = prompt.trim();
    final tooShort = trimmed.isNotEmpty && trimmed.length < 10;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Describe your goal in plain words',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            minLines: 4,
            maxLines: 7,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. I want to learn DSA step by step for placements in 3 months',
              border: OutlineInputBorder(),
            ),
          ),
          if (tooShort)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Be more specific',
                style: TextStyle(color: cs.error, fontSize: 12),
              ),
            ),
          const SizedBox(height: 14),
          Text(
            'Try these',
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _AiGoalSheetState._suggestions.keys
                .map(
                  (label) => ActionChip(
                    label: Text(label),
                    onPressed: () => onPickSuggestion(label),
                  ),
                )
                .toList(),
          ),
          if (errorMessage != null && errorMessage!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.error.withOpacity(0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.error_outline, color: cs.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            errorMessage!,
                            style: TextStyle(color: cs.error),
                          ),
                        ),
                        if (!errorMessage!.contains('No API key'))
                          TextButton(onPressed: onGenerate, child: const Text('Retry')),
                      ],
                    ),
                    if (technicalDetails != null && technicalDetails!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: EdgeInsets.zero,
                          shape: const Border(),
                          collapsedShape: const Border(),
                          title: Text(
                            'Technical details',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: cs.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: cs.outline.withOpacity(0.5)),
                              ),
                              child: SelectableText(
                                technicalDetails!,
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 18),
          _GradientButton(
            onPressed: trimmed.isEmpty ? null : onGenerate,
            gradient: gradient,
            icon: Icons.auto_awesome,
            label: 'Generate My Roadmap',
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Powered by Google Gemini',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView({
    required this.gradient,
    required this.subtitle,
  });

  final LinearGradient gradient;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShaderMask(
            shaderCallback: gradient.createShader,
            child: const Icon(Icons.auto_awesome, size: 56, color: Colors.white),
          )
              .animate(onPlay: (controller) => controller.repeat())
              .shimmer(duration: 1500.ms, color: const Color(0xFF5B9CF6))
              .scale(
                begin: const Offset(0.9, 0.9),
                end: const Offset(1.1, 1.1),
                duration: 800.ms,
                curve: Curves.easeInOut,
              )
              .then()
              .scale(
                begin: const Offset(1.1, 1.1),
                end: const Offset(0.9, 0.9),
                duration: 800.ms,
                curve: Curves.easeInOut,
              ),
          const SizedBox(height: 20),
          Text(
            'Generating your roadmap...',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 220,
            child: LinearProgressIndicator(
              minHeight: 8,
              borderRadius: BorderRadius.circular(999),
              color: const Color(0xFF5B9CF6),
              backgroundColor: cs.surfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              subtitle,
              key: ValueKey(subtitle),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewView extends StatelessWidget {
  const _PreviewView({
    required this.response,
    required this.expandedMilestones,
    required this.onToggleMilestone,
    required this.onEditPrompt,
    required this.onTryAgain,
    required this.onSave,
  });

  final AiGoalResponse response;
  final Set<int> expandedMilestones;
  final ValueChanged<int> onToggleMilestone;
  final VoidCallback onEditPrompt;
  final VoidCallback onTryAgain;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final goalColor = _parseGoalColor(response.goal.colorHex);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Your Roadmap is Ready!',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(onPressed: onEditPrompt, child: const Text('Edit prompt')),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surfaceVariant,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outline),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(response.goal.emoji, style: const TextStyle(fontSize: 30)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      response.goal.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(response.goal.description),
                    const SizedBox(height: 6),
                    Text(
                      'Duration: ${response.goal.durationLabel}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: goalColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '${response.milestones.length} milestones · ${response.totalTasks} tasks',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: response.milestones.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final milestone = response.milestones[index];
              final expanded = expandedMilestones.contains(index);

              return AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                decoration: BoxDecoration(
                  color: cs.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outline),
                ),
                child: Column(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onToggleMilestone(index),
                      child: Row(
                        children: [
                          Container(
                            width: 4,
                            height: 52,
                            decoration: BoxDecoration(
                              color: goalColor,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(12),
                                bottomLeft: Radius.circular(12),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${milestone.title} · ${milestone.theme}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${milestone.tasks.length} tasks',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: AnimatedRotation(
                              duration: const Duration(milliseconds: 200),
                              turns: expanded ? 0.5 : 0,
                              child: const Icon(Icons.expand_more),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (expanded)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                        child: Column(
                          children: milestone.tasks
                              .map(
                                (task) => Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('•', style: TextStyle(fontSize: 16)),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(task.text)),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onTryAgain,
                child: const Text('Try Again'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.check),
                label: const Text('Save to My Goals'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Color _parseGoalColor(String hex) {
    final normalized = hex.trim().replaceFirst('#', '');
    if (normalized.length != 6) return const Color(0xFF5B9CF6);
    return Color(int.tryParse('FF$normalized', radix: 16) ?? 0xFF5B9CF6);
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.onPressed,
    required this.gradient,
    required this.icon,
    required this.label,
  });

  final VoidCallback? onPressed;
  final LinearGradient gradient;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.55 : 1,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(14),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onPressed,
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
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
}
