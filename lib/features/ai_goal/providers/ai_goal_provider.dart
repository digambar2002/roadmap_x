import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/ai/gemini_provider.dart';
import '../../../core/ai/gemini_service.dart';
import '../../goals/providers/goal_provider.dart';
import '../../milestones/providers/milestone_provider.dart';
import '../../tasks/providers/task_provider.dart';

enum AiGenerationStatus { idle, loading, success, error }

typedef AiGoalGeneratorState = ({
  AiGenerationStatus status,
  AiGoalResponse? result,
  String? errorMessage,
  String? technicalDetails,
  String prompt,
});

class AiGoalGenerator extends Notifier<AiGoalGeneratorState> {
  static const Duration _requestCooldown = Duration(seconds: 8);
  DateTime? _lastRequestAt;

  @override
  AiGoalGeneratorState build() {
    return (
      status: AiGenerationStatus.idle,
      result: null,
      errorMessage: null,
      technicalDetails: null,
      prompt: '',
    );
  }

  void setPrompt(String prompt) {
    state = (
      status: state.status,
      result: state.result,
      errorMessage: state.errorMessage,
      technicalDetails: state.technicalDetails,
      prompt: prompt,
    );
  }

  Future<void> generate() async {
    if (state.status == AiGenerationStatus.loading) return;

    final now = DateTime.now();
    if (_lastRequestAt != null) {
      final elapsed = now.difference(_lastRequestAt!);
      if (elapsed < _requestCooldown) {
        final remaining = (_requestCooldown - elapsed).inSeconds + 1;
        state = (
          status: AiGenerationStatus.error,
          result: null,
          errorMessage: 'Please wait $remaining seconds before trying again.',
          technicalDetails: null,
          prompt: state.prompt,
        );
        return;
      }
    }

    final trimmed = state.prompt.trim();
    if (trimmed.isEmpty) return;

    if (trimmed.length < 10) {
      state = (
        status: AiGenerationStatus.error,
        result: null,
        errorMessage: 'Be more specific (at least 10 characters).',
        technicalDetails: null,
        prompt: state.prompt,
      );
      return;
    }

    final service = ref.read(geminiServiceProvider);
    if (service == null) {
      state = (
        status: AiGenerationStatus.error,
        result: null,
        errorMessage: 'No API key set. Go to Settings -> AI Configuration.',
        technicalDetails: null,
        prompt: state.prompt,
      );
      return;
    }

    state = (
      status: AiGenerationStatus.loading,
      result: null,
      errorMessage: null,
      technicalDetails: null,
      prompt: state.prompt,
    );
    _lastRequestAt = now;

    try {
      final result = await service.generateGoal(trimmed);
      state = (
        status: AiGenerationStatus.success,
        result: result,
        errorMessage: null,
        technicalDetails: null,
        prompt: state.prompt,
      );
    } on GeminiException catch (e) {
      state = (
        status: AiGenerationStatus.error,
        result: null,
        errorMessage: e.message,
        technicalDetails: e.debugDetails,
        prompt: state.prompt,
      );
    } catch (e) {
      state = (
        status: AiGenerationStatus.error,
        result: null,
        errorMessage: 'Something went wrong. Try again.',
        technicalDetails: e.toString(),
        prompt: state.prompt,
      );
    }
  }

  Future<int?> saveToDatabase() async {
    final result = state.result;
    if (result == null) return null;

    final goalRepo = ref.read(goalRepositoryProvider);
    final milestoneRepo = ref.read(milestoneRepositoryProvider);
    final taskRepo = ref.read(taskRepositoryProvider);

    try {
      final goal = await goalRepo.create(
        name: result.goal.name.isEmpty ? 'Untitled Goal' : result.goal.name,
        description: result.goal.description,
        emoji: result.goal.emoji.isEmpty ? '🎯' : result.goal.emoji,
        colorHex: _parseColorHex(result.goal.colorHex),
        targetDate: _targetDateFromDuration(result.goal.durationLabel),
      );

      for (final milestone in result.milestones..sort((a, b) => a.order.compareTo(b.order))) {
        final savedMilestone = await milestoneRepo.create(
          goalId: goal.id,
          title: milestone.title.isEmpty ? 'Milestone' : milestone.title,
          theme: milestone.theme,
        );

        final orderedTasks = [...milestone.tasks]..sort((a, b) => a.order.compareTo(b.order));
        for (final task in orderedTasks) {
          await taskRepo.create(
            milestoneId: savedMilestone.id,
            text: task.text,
            priority: task.priority.clamp(0, 2),
          );
        }
      }

      reset();
      return goal.id;
    } catch (e) {
      state = (
        status: AiGenerationStatus.error,
        result: state.result,
        errorMessage: 'Failed to save goal. Please try again.',
        technicalDetails: e.toString(),
        prompt: state.prompt,
      );
      return null;
    }
  }

  void toInput() {
    state = (
      status: AiGenerationStatus.idle,
      result: null,
      errorMessage: null,
      technicalDetails: null,
      prompt: state.prompt,
    );
  }

  void reset() {
    state = (
      status: AiGenerationStatus.idle,
      result: null,
      errorMessage: null,
      technicalDetails: null,
      prompt: '',
    );
  }

  int _parseColorHex(String colorHex) {
    final normalized = colorHex.trim().replaceFirst('#', '').toUpperCase();
    if (normalized.length != 6) return 0xFF5B9CF6;
    return int.tryParse('FF$normalized', radix: 16) ?? 0xFF5B9CF6;
  }

  DateTime _targetDateFromDuration(String label) {
    final now = DateTime.now();
    final lower = label.toLowerCase();
    final number = int.tryParse(RegExp(r'\d+').stringMatch(lower) ?? '');

    if (number == null) return now.add(const Duration(days: 90));
    if (lower.contains('week')) return now.add(Duration(days: number * 7));
    if (lower.contains('month')) return now.add(Duration(days: number * 30));
    if (lower.contains('year')) return now.add(Duration(days: number * 365));

    return now.add(const Duration(days: 90));
  }
}

final aiGoalGeneratorProvider = NotifierProvider<AiGoalGenerator, AiGoalGeneratorState>(
  AiGoalGenerator.new,
);
