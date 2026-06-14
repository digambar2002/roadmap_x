import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:google_generative_ai/google_generative_ai.dart';

class AiCoachService {
  final String apiKey;
  final String model;
  final GenerativeModel _model;

  AiCoachService({
    required this.apiKey,
    required this.model,
  }) : _model = GenerativeModel(
          model: model,
          apiKey: apiKey,
          generationConfig: GenerationConfig(
            temperature: 0.6,
            topK: 32,
            topP: 0.95,
            maxOutputTokens: 2048,
            responseMimeType: 'application/json',
          ),
        );

  Future<DailyBriefing> generateDailyBriefing({
    required String context,
    required DateTime today,
  }) async {
    final prompt = '''
You are AI Coach for a personal productivity app.
Return only JSON, no markdown.

Date: ${today.toIso8601String()}

Context:
$context

Respond in this shape:
{
  "headline": "string",
  "focus_task": "string",
  "quick_win": "string",
  "risk": "string",
  "coach_tip": "string"
}

Rules:
- Keep each field concise (1 sentence, max 120 chars).
- Focus on practical actions for today.
- Do not use generic motivational fluff.
''';

    final data = await _requestJson(prompt);
    return DailyBriefing.fromJson(data);
  }

  Future<WeeklyCoachReview> generateWeeklyReview({
    required String context,
    required DateTime weekStart,
  }) async {
    final prompt = '''
You are AI Coach for weekly reflection.
Return only JSON.

Week start: ${weekStart.toIso8601String()}

Context:
$context

Respond in this shape:
{
  "summary": "string",
  "wins": ["string"],
  "blockers": ["string"],
  "next_week_focus": ["string"],
  "consistency_score": 0
}

Rules:
- Provide 2-4 wins.
- Provide 1-3 blockers.
- Provide 2-4 next_week_focus items.
- consistency_score is integer 0-100.
- Keep it constructive and specific.
''';

    final data = await _requestJson(prompt);
    return WeeklyCoachReview.fromJson(data);
  }

  Future<PlanAdjustment> generatePlanAdjustment({
    required int goalId,
    required String context,
    String userInstruction = '',
  }) async {
    final prompt = '''
You are AI Coach helping adjust an execution plan.
Return only JSON.

Goal id: $goalId

Context:
$context

User instruction:
${userInstruction.trim().isEmpty ? 'No custom instruction provided.' : userInstruction}

Respond in this shape:
{
  "rationale": "string",
  "task_changes": ["string"],
  "milestone_changes": ["string"],
  "pace_advice": "string"
}

Rules:
- Keep recommendations realistic and actionable.
- Suggest re-ordering/splitting tasks when useful.
- Do not invent impossible effort expectations.
''';

    final data = await _requestJson(prompt);
    return PlanAdjustment.fromJson(data);
  }

  Future<CoachChatMessage> chat({
    required int goalId,
    required String context,
    required List<CoachChatMessage> history,
    required String userMessage,
  }) async {
    final historyLines = history
        .map((m) => '${m.role.name.toUpperCase()}: ${m.message}')
        .join('\n');

    final prompt = '''
You are AI Coach for a productivity app.
Return only JSON.

Goal id: $goalId

Context:
$context

Conversation history:
$historyLines

Latest user message:
$userMessage

Respond in this shape:
{
  "reply": "string"
}

Rules:
- Keep reply concise (2-5 sentences).
- Give concrete next action when possible.
- Be candid but supportive.
''';

    final data = await _requestJson(prompt);
    return CoachChatMessage(
      role: CoachChatRole.coach,
      message: (data['reply'] ?? '').toString().trim(),
      createdAt: DateTime.now(),
    );
  }

  Future<Map<String, dynamic>> _requestJson(String prompt) async {
    try {
      final response = await _model
          .generateContent([Content.text(prompt)])
          .timeout(const Duration(seconds: 30));
      final raw = response.text;
      if (raw == null || raw.trim().isEmpty) {
        throw AiCoachException('AI returned an empty response.');
      }
      return jsonDecode(raw) as Map<String, dynamic>;
    } on TimeoutException {
      throw AiCoachException('Request timed out. Please retry.');
    } on SocketException {
      throw AiCoachException('No internet connection.');
    } on FormatException {
      throw AiCoachException('AI returned invalid JSON. Please retry.');
    } on GenerativeAIException catch (e, st) {
      developer.log(
        '[AiCoach] ${e.message}',
        name: 'AiCoachService',
        error: e,
        stackTrace: st,
      );
      throw AiCoachException('AI service error. Please try again.');
    }
  }
}

class DailyBriefing {
  final String headline;
  final String focusTask;
  final String quickWin;
  final String risk;
  final String coachTip;
  final DateTime generatedAt;

  const DailyBriefing({
    required this.headline,
    required this.focusTask,
    required this.quickWin,
    required this.risk,
    required this.coachTip,
    required this.generatedAt,
  });

  factory DailyBriefing.fromJson(Map<String, dynamic> json) {
    return DailyBriefing(
      headline: (json['headline'] ?? '').toString().trim(),
      focusTask: (json['focus_task'] ?? '').toString().trim(),
      quickWin: (json['quick_win'] ?? '').toString().trim(),
      risk: (json['risk'] ?? '').toString().trim(),
      coachTip: (json['coach_tip'] ?? '').toString().trim(),
      generatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'headline': headline,
        'focus_task': focusTask,
        'quick_win': quickWin,
        'risk': risk,
        'coach_tip': coachTip,
        'generated_at': generatedAt.toIso8601String(),
      };
}

class WeeklyCoachReview {
  final String summary;
  final List<String> wins;
  final List<String> blockers;
  final List<String> nextWeekFocus;
  final int consistencyScore;
  final DateTime generatedAt;

  const WeeklyCoachReview({
    required this.summary,
    required this.wins,
    required this.blockers,
    required this.nextWeekFocus,
    required this.consistencyScore,
    required this.generatedAt,
  });

  factory WeeklyCoachReview.fromJson(Map<String, dynamic> json) {
    List<String> toStringList(Object? value) {
      if (value is! List) return const [];
      return value.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }

    return WeeklyCoachReview(
      summary: (json['summary'] ?? '').toString().trim(),
      wins: toStringList(json['wins']),
      blockers: toStringList(json['blockers']),
      nextWeekFocus: toStringList(json['next_week_focus']),
      consistencyScore: ((json['consistency_score'] as num?)?.toInt() ?? 0).clamp(0, 100),
      generatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'summary': summary,
        'wins': wins,
        'blockers': blockers,
        'next_week_focus': nextWeekFocus,
        'consistency_score': consistencyScore,
        'generated_at': generatedAt.toIso8601String(),
      };
}

class PlanAdjustment {
  final String rationale;
  final List<String> taskChanges;
  final List<String> milestoneChanges;
  final String paceAdvice;
  final DateTime generatedAt;

  const PlanAdjustment({
    required this.rationale,
    required this.taskChanges,
    required this.milestoneChanges,
    required this.paceAdvice,
    required this.generatedAt,
  });

  factory PlanAdjustment.fromJson(Map<String, dynamic> json) {
    List<String> toStringList(Object? value) {
      if (value is! List) return const [];
      return value.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }

    return PlanAdjustment(
      rationale: (json['rationale'] ?? '').toString().trim(),
      taskChanges: toStringList(json['task_changes']),
      milestoneChanges: toStringList(json['milestone_changes']),
      paceAdvice: (json['pace_advice'] ?? '').toString().trim(),
      generatedAt: DateTime.now(),
    );
  }
}

enum CoachChatRole { user, coach }

class CoachChatMessage {
  final CoachChatRole role;
  final String message;
  final DateTime createdAt;

  const CoachChatMessage({
    required this.role,
    required this.message,
    required this.createdAt,
  });
}

class AiCoachException implements Exception {
  final String message;
  const AiCoachException(this.message);

  @override
  String toString() => message;
}
