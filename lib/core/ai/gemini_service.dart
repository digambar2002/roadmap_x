import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  final String apiKey;
  final String model;
  final GenerativeModel _model;

  GeminiService({
    required this.apiKey,
    required this.model,
  }) : _model = GenerativeModel(
          model: model,
          apiKey: apiKey,
          generationConfig: GenerationConfig(
            temperature: 0.7,
            topK: 40,
            topP: 0.95,
              maxOutputTokens: 2048,
            responseMimeType: 'application/json',
          ),
        );

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

    try {
      return await _requestAndParse(prompt);
    } on TimeoutException catch (e, st) {
      _logSdkError('Timeout', e, st);
      throw GeminiException('Request timed out. Check your connection.');
    } on SocketException catch (e, st) {
      _logSdkError('SocketException', e, st);
      throw GeminiException('No internet connection.');
    } on FormatException catch (e, st) {
      _logSdkError('FormatException', e, st);
      throw GeminiException('AI returned unexpected format. Retry.');
    } on GenerativeAIException catch (e, st) {
      _logSdkError('GenerativeAIException', e, st);
      final details = _redact(e.toString());
      final msg = e.message.toLowerCase();
      if (msg.contains('model') && (msg.contains('not found') || msg.contains('not supported') || msg.contains('unavailable'))) {
        throw GeminiException(
          'Selected model is not available for this API key. Choose Gemini 2.5 Flash in Settings.',
          debugDetails: details,
        );
      }
      if (msg.contains('429') || msg.contains('rate')) {
        // One controlled retry with a short backoff helps transient quota spikes.
        try {
          await Future<void>.delayed(const Duration(seconds: 2));
          return await _requestAndParse(prompt);
        } on GenerativeAIException catch (retryError, retryStack) {
          _logSdkError('GenerativeAIException(retry)', retryError, retryStack);
          throw GeminiException(
            'Too many requests. Wait 10-20 seconds and try again.',
            debugDetails: _redact(retryError.toString()),
          );
        }
      }
      if (msg.contains('400') || msg.contains('api key') || msg.contains('permission')) {
        throw GeminiException('API key is invalid. Check Settings.', debugDetails: details);
      }
      if (msg.contains('503') || msg.contains('unavailable')) {
        throw GeminiException('Gemini is overloaded. Try again shortly.', debugDetails: details);
      }
      throw GeminiException('Gemini error. Try again.', debugDetails: details);
    }
  }

  Future<AiGoalResponse> _requestAndParse(String prompt) async {
    final response = await _model
        .generateContent([Content.text(prompt)])
        .timeout(const Duration(seconds: 30));

    final raw = response.text;
    if (raw == null || raw.trim().isEmpty) {
      throw GeminiException('AI returned an empty response. Try again.');
    }

    final jsonData = jsonDecode(raw) as Map<String, dynamic>;
    return AiGoalResponse.fromJson(jsonData);
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
    return AiGoalResponse(
      goal: AiGoal.fromJson(json['goal'] as Map<String, dynamic>),
      milestones: (json['milestones'] as List<dynamic>)
        .map((m) => AiMilestone.fromJson(m as Map<String, dynamic>))
        .toList()
        ..sort((a, b) => a.order.compareTo(b.order)),
    );
  }

  int get totalTasks => milestones.fold<int>(0, (sum, m) => sum + m.tasks.length);
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
    return AiMilestone(
      title: (json['title'] ?? '').toString(),
      theme: (json['theme'] ?? '').toString(),
      order: (json['order'] as num?)?.toInt() ?? 0,
      tasks: (json['tasks'] as List<dynamic>)
        .map((t) => AiTask.fromJson(t as Map<String, dynamic>))
        .toList()
        ..sort((a, b) => a.order.compareTo(b.order)),
    );
  }
}

class AiTask {
  final String text;
  final int priority;
  final int order;

  const AiTask({
    required this.text,
    required this.priority,
    required this.order,
  });

  factory AiTask.fromJson(Map<String, dynamic> json) {
    return AiTask(
      text: (json['text'] ?? '').toString(),
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      order: (json['order'] as num?)?.toInt() ?? 0,
    );
  }
}
