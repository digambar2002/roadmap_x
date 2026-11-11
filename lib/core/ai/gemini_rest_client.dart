import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// A failed Gemini call, with Google's own status and message.
class GeminiApiException implements Exception {
  const GeminiApiException({
    required this.httpStatus,
    required this.status,
    required this.message,
    this.details = '',
  });

  /// HTTP status code, or 0 when the response itself was unusable.
  final int httpStatus;

  /// Google's status string ("RESOURCE_EXHAUSTED", "NOT_FOUND", …) or one of
  /// ours: "EMPTY", "TRUNCATED", "BLOCKED".
  final String status;
  final String message;

  /// The raw `details` array (retry delay, quota ids), for classification.
  final String details;

  /// Everything, for matching on quota and retry hints.
  String get fullText => '$httpStatus $status $message $details';

  @override
  String toString() => 'GeminiApiException($httpStatus $status): $message';
}

/// Calls Gemini's `generateContent` REST endpoint directly.
///
/// This replaces the `google_generative_ai` Dart package, which Google has
/// deprecated and which predates the Gemini 3 models: it always sent `topK`,
/// which newer models can reject, it could fail to parse their "thinking"
/// response parts, and its error types hid what Google actually said.
/// Here the request carries only widely supported settings, thought parts
/// are skipped, and every failure keeps Google's status and message.
class GeminiRestClient {
  GeminiRestClient({required this.apiKey, http.Client? client})
      : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  static const _host = 'generativelanguage.googleapis.com';

  /// Returns the model's JSON text answer.
  Future<String> generateJson({
    required String model,
    required String prompt,
    double temperature = 0.7,
    // Room for the model's thinking as well as the answer: Gemini 3 thinks
    // by default, and 2048 tokens could be used up before any JSON appeared.
    int maxOutputTokens = 8192,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final uri = Uri.https(_host, '/v1beta/models/$model:generateContent');
    final body = jsonEncode({
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {
        'temperature': temperature,
        'topP': 0.95,
        'maxOutputTokens': maxOutputTokens,
        'responseMimeType': 'application/json',
      },
    });

    final response = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': apiKey,
          },
          body: body,
        )
        .timeout(timeout);

    // Always UTF-8: without a charset header `response.body` falls back to
    // Latin-1, which garbles emoji and non-English text.
    final decoded =
        _decode(utf8.decode(response.bodyBytes, allowMalformed: true));
    if (response.statusCode != 200) {
      final error = decoded is Map ? decoded['error'] : null;
      throw GeminiApiException(
        httpStatus: response.statusCode,
        status: error is Map ? '${error['status'] ?? ''}' : '',
        message: error is Map
            ? '${error['message'] ?? ''}'
            : 'HTTP ${response.statusCode}',
        details: error is Map && error['details'] != null
            ? jsonEncode(error['details'])
            : '',
      );
    }
    if (decoded is! Map) {
      throw const GeminiApiException(
        httpStatus: 0,
        status: 'EMPTY',
        message: 'Gemini returned an unreadable response.',
      );
    }

    final feedback = decoded['promptFeedback'];
    if (feedback is Map && feedback['blockReason'] != null) {
      throw GeminiApiException(
        httpStatus: 200,
        status: 'BLOCKED',
        message: 'Gemini declined this request (${feedback['blockReason']}).',
      );
    }

    final candidates = decoded['candidates'];
    final first =
        candidates is List && candidates.isNotEmpty ? candidates.first : null;
    final parts = first is Map && first['content'] is Map
        ? (first['content'] as Map)['parts']
        : null;
    final text = StringBuffer();
    if (parts is List) {
      for (final part in parts) {
        // Skip the model's thinking; keep only the answer.
        if (part is Map && part['thought'] != true && part['text'] is String) {
          text.write(part['text']);
        }
      }
    }
    final answer = _stripFences(text.toString().trim());
    if (answer.isEmpty) {
      final reason = first is Map ? '${first['finishReason'] ?? ''}' : '';
      throw GeminiApiException(
        httpStatus: 200,
        status: reason == 'MAX_TOKENS'
            ? 'TRUNCATED'
            : (reason == 'SAFETY' ? 'BLOCKED' : 'EMPTY'),
        message:
            'Gemini returned no answer${reason.isEmpty ? '' : ' ($reason)'}.',
      );
    }
    return answer;
  }

  static Object? _decode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  /// Models sometimes wrap JSON in a ```json fence despite the MIME type.
  static String _stripFences(String s) {
    final m = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$').firstMatch(s);
    return m == null ? s : m.group(1)!.trim();
  }
}

/// What to tell the user about a failed call, and whether the free model
/// should be tried instead.
enum GeminiFailure {
  rateLimited,
  modelNotFound,
  badKey,
  overloaded,
  rejected,
  truncated,
  blocked,
  empty,
}

GeminiFailure classifyGeminiError(GeminiApiException e) {
  final s = e.status.toUpperCase();
  final m = e.message.toLowerCase();
  if (e.httpStatus == 429 || s == 'RESOURCE_EXHAUSTED') {
    return GeminiFailure.rateLimited;
  }
  if (e.httpStatus == 404 || s == 'NOT_FOUND')
    return GeminiFailure.modelNotFound;
  if (e.httpStatus == 401 ||
      e.httpStatus == 403 ||
      s == 'PERMISSION_DENIED' ||
      s == 'UNAUTHENTICATED' ||
      m.contains('api key not valid') ||
      m.contains('api_key_invalid')) {
    return GeminiFailure.badKey;
  }
  if (e.httpStatus >= 500 || s == 'UNAVAILABLE' || s == 'INTERNAL') {
    return GeminiFailure.overloaded;
  }
  if (s == 'TRUNCATED') return GeminiFailure.truncated;
  if (s == 'BLOCKED') return GeminiFailure.blocked;
  if (s == 'EMPTY') return GeminiFailure.empty;
  return GeminiFailure.rejected;
}

/// A short, honest message for each failure. Unknown rejections show
/// Google's own words so the cause is never hidden again.
String geminiFailureMessage(
        GeminiFailure f, GeminiApiException e, String model) =>
    switch (f) {
      GeminiFailure.modelNotFound =>
        'Gemini doesn\'t recognise the model "$model" for this API key. '
            'Pick another model in Settings → AI coach.',
      GeminiFailure.badKey =>
        'Your Gemini API key was rejected. Check it in Settings → AI coach.',
      GeminiFailure.overloaded =>
        'Gemini is busy right now. Try again in a minute.',
      GeminiFailure.truncated =>
        'The answer was cut off. Try again, or shorten the text.',
      GeminiFailure.blocked =>
        'Gemini declined this request. Try rewording it.',
      GeminiFailure.empty => 'Gemini returned an empty answer. Try again.',
      GeminiFailure.rejected =>
        'Gemini couldn\'t process this: ${_short(e.message)}',
      GeminiFailure.rateLimited => 'Too many requests. Try again shortly.',
    };

String _short(String s) => s.length > 160
    ? '${s.substring(0, 157)}…'
    : (s.isEmpty ? 'unknown error' : s);
