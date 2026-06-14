import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/ai/ai_coach_service.dart';
import '../../../core/services/shared_preferences_provider.dart';
import '../../settings/providers/ai_settings_provider.dart';
import '../data/coach_cache_repository.dart';
import '../data/coach_context_builder.dart';

final coachContextBuilderProvider = Provider<CoachContextBuilder>(
  (_) => CoachContextBuilder(),
);

final coachCacheRepositoryProvider = Provider<CoachCacheRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return CoachCacheRepository(prefs);
});

/// Watches notifier state so UI updates immediately after saving API key.
final hasAiCoachProvider = Provider<bool>((ref) {
  final settings = ref.watch(aiSettingsNotifierProvider);
  final key = settings.apiKey;
  return key != null && key.isNotEmpty;
});

final aiCoachServiceProvider = Provider<AiCoachService?>((ref) {
  if (!ref.watch(hasAiCoachProvider)) return null;
  final settings = ref.watch(aiSettingsNotifierProvider);
  final apiKey = settings.apiKey;
  if (apiKey == null || apiKey.isEmpty) return null;
  return AiCoachService(apiKey: apiKey, model: settings.model);
});

class DailyBriefingNotifier extends AsyncNotifier<DailyBriefing?> {
  @override
  Future<DailyBriefing?> build() async {
    ref.listen(hasAiCoachProvider, (previous, next) {
      if (next == true && previous != true) {
        refresh();
      }
    });

    if (!ref.watch(hasAiCoachProvider)) return null;

    try {
      return await _load(forceRefresh: false);
    } catch (e) {
      throw e is AiCoachException ? e : AiCoachException(e.toString());
    }
  }

  Future<void> refresh() async {
    if (!ref.read(hasAiCoachProvider)) {
      state = const AsyncData(null);
      return;
    }
    state = const AsyncLoading();
    state = AsyncData(await _load(forceRefresh: true));
  }

  Future<void> load({bool forceRefresh = false}) async {
    if (forceRefresh) {
      await refresh();
      return;
    }
    if (!ref.read(hasAiCoachProvider)) {
      state = const AsyncData(null);
      return;
    }
    if (state.isLoading) return;
    state = const AsyncLoading();
    state = AsyncData(await _load(forceRefresh: false));
  }

  Future<DailyBriefing?> _load({required bool forceRefresh}) async {
    final service = ref.read(aiCoachServiceProvider);
    if (service == null) {
      throw const AiCoachException('Add your Gemini API key in Settings.');
    }

    final now = DateTime.now();
    final cache = ref.read(coachCacheRepositoryProvider);

    if (!forceRefresh) {
      final cached = cache.readDaily(now);
      if (cached != null) return cached;
    }

    final context =
        await ref.read(coachContextBuilderProvider).buildGlobalContext();
    final briefing = await service.generateDailyBriefing(
      context: context,
      today: now,
    );
    await cache.saveDaily(briefing, now);
    return briefing;
  }
}

final dailyBriefingProvider =
    AsyncNotifierProvider<DailyBriefingNotifier, DailyBriefing?>(
  DailyBriefingNotifier.new,
);

class WeeklyCoachReviewNotifier extends AsyncNotifier<WeeklyCoachReview?> {
  @override
  Future<WeeklyCoachReview?> build() async => null;

  Future<void> load({bool forceRefresh = false}) async {
    if (!ref.read(hasAiCoachProvider)) {
      state = const AsyncData(null);
      return;
    }

    final service = ref.read(aiCoachServiceProvider);
    if (service == null) {
      state = AsyncError(
        const AiCoachException('Add your Gemini API key in Settings.'),
        StackTrace.current,
      );
      return;
    }

    state = const AsyncLoading();

    try {
      final today = DateTime.now();
      final weekStart = DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: today.weekday - 1));

      final cache = ref.read(coachCacheRepositoryProvider);
      if (!forceRefresh) {
        final cached = cache.readWeekly(weekStart);
        if (cached != null) {
          state = AsyncData(cached);
          return;
        }
      }

      final context =
          await ref.read(coachContextBuilderProvider).buildGlobalContext();
      final review = await service.generateWeeklyReview(
        context: context,
        weekStart: weekStart,
      );
      await cache.saveWeekly(review, weekStart);
      state = AsyncData(review);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

final weeklyCoachReviewProvider =
    AsyncNotifierProvider<WeeklyCoachReviewNotifier, WeeklyCoachReview?>(
  WeeklyCoachReviewNotifier.new,
);

void refreshAiCoachAfterSettingsChange(WidgetRef ref) {
  ref.invalidate(dailyBriefingProvider);
  ref.invalidate(weeklyCoachReviewProvider);
}

class AdjustPlanNotifier extends FamilyAsyncNotifier<PlanAdjustment?, int> {
  late int _goalId;

  @override
  Future<PlanAdjustment?> build(int arg) async {
    _goalId = arg;
    return null;
  }

  Future<void> generate({String userInstruction = ''}) async {
    final service = ref.read(aiCoachServiceProvider);
    if (service == null) {
      state = AsyncError(
        const AiCoachException('AI Coach is unavailable. Add API key in Settings.'),
        StackTrace.current,
      );
      return;
    }
    state = const AsyncLoading();
    try {
      final goalContext =
          await ref.read(coachContextBuilderProvider).buildGoalContext(_goalId);
      final adjustment = await service.generatePlanAdjustment(
        goalId: _goalId,
        context: goalContext,
        userInstruction: userInstruction,
      );
      state = AsyncData(adjustment);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

final adjustPlanProvider =
    AsyncNotifierProvider.family<AdjustPlanNotifier, PlanAdjustment?, int>(
  AdjustPlanNotifier.new,
);

class CoachChatState {
  final List<CoachChatMessage> messages;
  final bool isSending;
  final String? error;

  const CoachChatState({
    required this.messages,
    required this.isSending,
    required this.error,
  });

  factory CoachChatState.initial() => const CoachChatState(
        messages: [],
        isSending: false,
        error: null,
      );

  CoachChatState copyWith({
    List<CoachChatMessage>? messages,
    bool? isSending,
    String? error,
    bool clearError = false,
  }) {
    return CoachChatState(
      messages: messages ?? this.messages,
      isSending: isSending ?? this.isSending,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class CoachChatNotifier extends FamilyNotifier<CoachChatState, int> {
  late int _goalId;

  @override
  CoachChatState build(int arg) {
    _goalId = arg;
    return CoachChatState.initial();
  }

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.isSending) return;

    final userMessage = CoachChatMessage(
      role: CoachChatRole.user,
      message: trimmed,
      createdAt: DateTime.now(),
    );
    final history = [...state.messages, userMessage];
    state = state.copyWith(
      messages: history,
      isSending: true,
      clearError: true,
    );

    final service = ref.read(aiCoachServiceProvider);
    if (service == null) {
      state = state.copyWith(
        isSending: false,
        error: 'AI Coach is unavailable. Add API key in Settings.',
      );
      return;
    }

    try {
      final context =
          await ref.read(coachContextBuilderProvider).buildGoalContext(_goalId);
      final reply = await service.chat(
        goalId: _goalId,
        context: context,
        history: history,
        userMessage: trimmed,
      );
      state = state.copyWith(
        messages: [...history, reply],
        isSending: false,
      );
    } catch (e) {
      state = state.copyWith(
        isSending: false,
        error: e is AiCoachException ? e.message : e.toString(),
      );
    }
  }

  void clear() {
    state = CoachChatState.initial();
  }
}

final coachChatProvider =
    NotifierProvider.family<CoachChatNotifier, CoachChatState, int>(
  CoachChatNotifier.new,
);
