import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:http/http.dart' as http;

import 'ai_rate_limiter.dart';
import 'gemini_rest_client.dart';

class GeminiService {
  final String apiKey;
  final String model;
  final GeminiRestClient _api;

  GeminiService({
    required this.apiKey,
    required this.model,
    http.Client? httpClient,
  }) : _api = GeminiRestClient(apiKey: apiKey, client: httpClient);

  Future<AiGoalResponse> generateGoal(String userPrompt) async {
    const systemInstruction = '''
You are a smart productivity and goal-planning assistant.
The user will describe a goal they want to achieve.
You must return a JSON object with no extra text, no markdown, and no code fences.

{
  "goal": {
    "name": "string (max 60 chars, clear and specific)",
    "description": "string (1-2 sentences explaining the goal)",
    "emoji": "string (single relevant emoji)",
    "color_hex": "string (pick from: #5B9CF6, #34D399, #FBBF24, #F472B6, #A78BFA, #FB923C, #2DD4BF, #38BDF8, #A3E635, #F87171)",
    "duration_label": "string (e.g. '3 Months', '6 Weeks', '1 Year')"
  },
  "milestones": [
    {
      "title": "string (e.g. 'Month 1', 'Week 1-2', 'Phase 1')",
      "theme": "string (short theme e.g. 'Foundations', 'Core Concepts')",
      "order": 1,
      "tasks": [
        {
          "text": "string (specific, actionable task — start with a verb)",
          "priority": 0,
          "order": 1
        }
      ]
    }
  ]
}

Rules:
- priority: 0 = Normal, 1 = High, 2 = Critical
- Create 2-4 milestones based on the goal scope
- Create 4-8 tasks per milestone (specific, actionable)
- Tasks must start with action verbs
- Milestones must progress logically from beginner to advanced
- Total tasks should be between 15 and 35
- emoji must be a single emoji character relevant to the goal
- color_hex must be one of the provided options
- Return only the JSON object
''';

    final prompt = '''
$systemInstruction

User goal request:
$userPrompt
''';

    return _run(prompt);
  }

  /// Turns text the user pasted (notes, a plan, a list, an email) into a goal
  /// with milestones and tasks, keeping their own wording.
  Future<AiGoalResponse> structurePlan(String pastedText) async {
    const systemInstruction = '''
You organise a plan the user pasted into a goal, milestones and tasks.
Return a JSON object with no extra text, no markdown, and no code fences,
in exactly this shape:

{
  "goal": {
    "name": "string (max 60 chars)",
    "description": "string (1-2 sentences)",
    "emoji": "string (single relevant emoji)",
    "color_hex": "string (pick from: #5B9CF6, #34D399, #FBBF24, #F472B6, #A78BFA, #FB923C, #2DD4BF, #38BDF8, #A3E635, #F87171)",
    "duration_label": "string (e.g. '3 Months', '6 Weeks')"
  },
  "milestones": [
    {
      "title": "string",
      "theme": "string",
      "order": 1,
      "tasks": [
        { "text": "string", "priority": 0, "order": 1 }
      ]
    }
  ]
}

Rules:
- Keep the user's own wording for tasks. Fix only obvious typos.
- Every actionable item in the text must become exactly one task.
- Do not invent extra tasks. Only if the text is a short description with no
  concrete steps, propose a small set of actionable tasks.
- Use the text's headings, weeks, phases or sections as milestones; if it has
  none, group related tasks into 1-4 logical milestones.
- Ignore greetings, signatures and chit-chat.
- priority: 2 for urgent/critical items, 1 for important/high, otherwise 0.
- Return only the JSON object.
''';

    final prompt = '''
$systemInstruction

Pasted text:
$pastedText
''';

    return _run(prompt);
  }

  /// Sends a prompt and maps every failure to a friendly [GeminiException].
  Future<AiGoalResponse> _run(String prompt, {bool isFallback = false}) async {
    final limiter = AiRateLimiter.instance;
    final blocked = limiter.blockReason();
    if (blocked != null) throw GeminiException(blocked);
    final modelName = limiter.modelFor(model);
    limiter.record();
    try {
      final raw = await _api.generateJson(model: modelName, prompt: prompt);
      return _parse(raw);
    } on TimeoutException catch (e, st) {
      _logSdkError('Timeout', e, st);
      throw GeminiException('Request timed out. Check your connection.');
    } on SocketException catch (e, st) {
      _logSdkError('SocketException', e, st);
      throw GeminiException('No internet connection.');
    } on http.ClientException catch (e, st) {
      _logSdkError('ClientException', e, st);
      throw GeminiException('No internet connection.');
    } on GeminiApiException catch (e, st) {
      _logSdkError('GeminiApiException', e, st);
      final details = _redact(e.fullText);
      final failure = classifyGeminiError(e);
      if (failure == GeminiFailure.rateLimited) {
        // No blind retry: it only spends another request from the same
        // quota. Wait as long as Gemini asks, or switch to the free model
        // when this one has no free quota at all.
        final kind = limiter.onRateLimited(e.fullText, model: modelName);
        if (kind == RateLimitKind.modelNotFree &&
            !isFallback &&
            modelName != AiRateLimiter.freeModel) {
          return _run(prompt, isFallback: true);
        }
        throw GeminiException(limiter.messageFor(kind), debugDetails: details);
      }
      throw GeminiException(
        geminiFailureMessage(failure, e, modelName),
        debugDetails: details,
      );
    }
  }

  AiGoalResponse _parse(String raw) {
    // The model can return a top-level array or omit expected keys even
    // with a JSON response type; surface that as a typed GeminiException
    // instead of an uncaught TypeError.
    try {
      final jsonData = jsonDecode(raw);
      if (jsonData is! Map<String, dynamic>) {
        throw const FormatException('Top-level JSON is not an object');
      }
      return AiGoalResponse.fromJson(jsonData);
    } catch (e) {
      throw GeminiException(
        'AI returned an unexpected format. Try again.',
        debugDetails: _redact(e.toString()),
      );
    }
  }

  void _logSdkError(String type, Object error, StackTrace stackTrace) {
    developer.log(
      '[Gemini][$type] ${_redact(error.toString())}',
      name: 'GeminiService',
      error: _redact(error.toString()),
      stackTrace: stackTrace,
    );
  }

  String _redact(String input) {
    var output = input.replaceAll(apiKey, '[REDACTED_API_KEY]');
    output = output.replaceAll(
      RegExp(r'key=[^&\s]+', caseSensitive: false),
      'key=[REDACTED]',
    );
    output = output.replaceAll(
      RegExp(r'AIza[0-9A-Za-z_-]{20,}'),
      '[REDACTED_API_KEY]',
    );
    return output;
  }
}

class GeminiException implements Exception {
  final String message;
  final String? debugDetails;

  GeminiException(this.message, {this.debugDetails});

  @override
  String toString() => message;
}

class AiGoalResponse {
  final AiGoal goal;
  final List<AiMilestone> milestones;

  const AiGoalResponse({required this.goal, required this.milestones});

  factory AiGoalResponse.fromJson(Map<String, dynamic> json) {
    final goalJson = json['goal'];
    final milestonesJson = json['milestones'];
    if (goalJson is! Map<String, dynamic> || milestonesJson is! List) {
      throw const FormatException('Response is missing "goal" or "milestones"');
    }
    return AiGoalResponse(
      goal: AiGoal.fromJson(goalJson),
      milestones: milestonesJson
          .whereType<Map<String, dynamic>>()
          .map(AiMilestone.fromJson)
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order)),
    );
  }

  int get totalTasks =>
      milestones.fold<int>(0, (sum, m) => sum + m.tasks.length);
}

class AiGoal {
  final String name;
  final String description;
  final String emoji;
  final String colorHex;
  final String durationLabel;

  const AiGoal({
    required this.name,
    required this.description,
    required this.emoji,
    required this.colorHex,
    required this.durationLabel,
  });

  factory AiGoal.fromJson(Map<String, dynamic> json) {
    return AiGoal(
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      emoji: (json['emoji'] ?? '🎯').toString(),
      colorHex: (json['color_hex'] ?? '#5B9CF6').toString(),
      durationLabel: (json['duration_label'] ?? '3 Months').toString(),
    );
  }
}

class AiMilestone {
  final String title;
  final String theme;
  final int order;
  final List<AiTask> tasks;

  const AiMilestone({
    required this.title,
    required this.theme,
    required this.order,
    required this.tasks,
  });

  factory AiMilestone.fromJson(Map<String, dynamic> json) {
    final tasksJson = json['tasks'];
    return AiMilestone(
      title: (json['title'] ?? '').toString(),
      theme: (json['theme'] ?? '').toString(),
      order: (json['order'] as num?)?.toInt() ?? 0,
      tasks: (tasksJson is List ? tasksJson : const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(AiTask.fromJson)
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order)),
    );
  }
}

class AiTask {
  final String text;
  final int priority;
  final int order;

  /// Extra detail, e.g. the sub-points under a task in a pasted plan.
  final String note;

  const AiTask({
    required this.text,
    required this.priority,
    required this.order,
    this.note = '',
  });

  factory AiTask.fromJson(Map<String, dynamic> json) {
    return AiTask(
      text: (json['text'] ?? '').toString(),
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      order: (json['order'] as num?)?.toInt() ?? 0,
      note: (json['note'] ?? '').toString(),
    );
  }
}
