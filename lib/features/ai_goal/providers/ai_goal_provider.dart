import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/ai/gemini_provider.dart';
import '../../../core/ai/gemini_service.dart';
import '../data/goal_plan_saver.dart';

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
        // Keep an existing successful preview visible — flipping to the
        // error state here used to irrecoverably discard the generated
        // roadmap when "Try Again" was tapped within the cooldown.
        if (state.result != null &&
            state.status == AiGenerationStatus.success) {
          return;
        }
        final remaining = (_requestCooldown - elapsed).inSeconds + 1;
        state = (
          status: AiGenerationStatus.error,
          result: state.result,
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
    try {
      final goalId = await saveGoalPlan(result);
      reset();
      return goalId;
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
}

final aiGoalGeneratorProvider =
    NotifierProvider<AiGoalGenerator, AiGoalGeneratorState>(
  AiGoalGenerator.new,
);
