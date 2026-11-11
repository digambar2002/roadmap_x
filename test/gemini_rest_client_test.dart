import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:roadmap_x/core/ai/ai_rate_limiter.dart';
import 'package:roadmap_x/core/ai/gemini_rest_client.dart';
import 'package:roadmap_x/core/ai/gemini_service.dart';

const planJson = '{"goal":{"name":"Run a 10k","description":"","emoji":"🏃",'
    '"color_hex":"#34D399","duration_label":"6 Weeks"},"milestones":[{"title":'
    '"Week 1","theme":"Base","order":1,"tasks":[{"text":"Run 3 times",'
    '"priority":0,"order":1}]}]}';

http.Response json(Object body, int code) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      code,
      headers: {'content-type': 'application/json'},
    );

http.Response ok(String text, {bool withThought = true}) => json(
      {
        'candidates': [
          {
            'content': {
              'role': 'model',
              'parts': [
                if (withThought) {'text': 'thinking…', 'thought': true},
                {'text': text, 'thoughtSignature': 'abc'},
              ],
            },
            'finishReason': 'STOP',
          },
        ],
      },
      200,
    );

http.Response error(int code, String status, String message,
        [List<Object>? details]) =>
    json(
      {
        'error': {
          'code': code,
          'status': status,
          'message': message,
          if (details != null) 'details': details,
        },
      },
      code,
    );

void main() {
  setUp(AiRateLimiter.instance.reset);

  test('sends a lean request and returns only the answer, not the thinking',
      () async {
    late http.Request sent;
    final client = GeminiRestClient(
      apiKey: 'KEY',
      client: MockClient((req) async {
        sent = req;
        return ok('{"a":1}');
      }),
    );
    final out =
        await client.generateJson(model: 'gemini-3.8-flash', prompt: 'hi');
    expect(out, '{"a":1}');
    expect(sent.url.path, '/v1beta/models/gemini-3.8-flash:generateContent');
    expect(sent.headers['x-goog-api-key'], 'KEY');
    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    final config = body['generationConfig'] as Map<String, dynamic>;
    expect(config.containsKey('topK'), isFalse,
        reason: 'newer models can reject topK');
    expect(config['maxOutputTokens'], 8192, reason: 'room for thinking');
  });

  test('a rejected setting shows Google\'s words, not "model not available"',
      () async {
    final service = GeminiService(
      apiKey: 'KEY',
      model: 'gemini-3.8-flash',
      httpClient: MockClient((_) async => error(
          400, 'INVALID_ARGUMENT', 'Unknown name "foo": Cannot find field.')),
    );
    await expectLater(
      service.structurePlan('Learn Spanish\n- Words'),
      throwsA(isA<GeminiException>().having(
        (e) => e.message,
        'message',
        allOf(contains('Cannot find field'), isNot(contains('not available')),
            isNot(contains('API key'))),
      )),
    );
  });

  test('404 says the model is not recognised, by name', () async {
    final service = GeminiService(
      apiKey: 'KEY',
      model: 'gemini-9-ultra',
      httpClient: MockClient((_) async =>
          error(404, 'NOT_FOUND', 'models/gemini-9-ultra is not found')),
    );
    await expectLater(
      service.structurePlan('Plan\n- a'),
      throwsA(isA<GeminiException>()
          .having((e) => e.message, 'message', contains('gemini-9-ultra'))),
    );
  });

  test('503 overload is reported as busy, not as a bad model', () async {
    final service = GeminiService(
      apiKey: 'KEY',
      model: 'gemini-3.8-flash',
      httpClient: MockClient((_) async => error(503, 'UNAVAILABLE',
          'The model is overloaded. Please try again later.')),
    );
    await expectLater(
      service.structurePlan('Plan\n- a'),
      throwsA(isA<GeminiException>()
          .having((e) => e.message, 'message', contains('busy'))),
    );
  });

  test('429 honours the retry delay and blocks further calls', () async {
    var calls = 0;
    final service = GeminiService(
      apiKey: 'KEY',
      model: 'gemini-3.8-flash',
      httpClient: MockClient((_) async {
        calls++;
        return error(429, 'RESOURCE_EXHAUSTED', 'Quota exceeded.', [
          {
            '@type': 'type.googleapis.com/google.rpc.RetryInfo',
            'retryDelay': '40s'
          },
        ]);
      }),
    );
    await expectLater(
        service.structurePlan('Plan\n- a'), throwsA(isA<GeminiException>()));
    await expectLater(
      service.structurePlan('Plan\n- a'),
      throwsA(isA<GeminiException>()
          .having((e) => e.message, 'message', contains('slow down'))),
    );
    expect(calls, 1, reason: 'the second call never reached Gemini');
  });

  test('a model with no free quota falls back to Flash and succeeds', () async {
    final models = <String>[];
    final service = GeminiService(
      apiKey: 'KEY',
      model: 'gemini-3.1-pro-preview',
      httpClient: MockClient((req) async {
        models.add(req.url.pathSegments.last);
        if (req.url.path.contains('pro')) {
          return error(429, 'RESOURCE_EXHAUSTED',
              'Quota exceeded for metric: generate_content_free_tier_requests, limit: 0');
        }
        return ok(planJson);
      }),
    );
    final plan = await service.structurePlan('Run a 10k\n- Run 3 times');
    expect(plan.goal.name, 'Run a 10k');
    expect(models, [
      'gemini-3.1-pro-preview:generateContent',
      'gemini-3.8-flash:generateContent',
    ]);
  });

  test('an answer cut off by the token limit says so', () async {
    final client = GeminiRestClient(
      apiKey: 'KEY',
      client: MockClient((_) async => json(
            {
              'candidates': [
                {
                  'content': {'parts': <Object>[]},
                  'finishReason': 'MAX_TOKENS'
                },
              ],
            },
            200,
          )),
    );
    await expectLater(
      client.generateJson(model: 'm', prompt: 'p'),
      throwsA(isA<GeminiApiException>()
          .having((e) => e.status, 'status', 'TRUNCATED')),
    );
  });

  test('a bad key is called out as a bad key', () async {
    final service = GeminiService(
      apiKey: 'nope',
      model: 'gemini-3.8-flash',
      httpClient: MockClient((_) async => error(400, 'INVALID_ARGUMENT',
          'API key not valid. Please pass a valid API key.')),
    );
    await expectLater(
      service.structurePlan('Plan\n- a'),
      throwsA(isA<GeminiException>().having(
          (e) => e.message, 'message', contains('API key was rejected'))),
    );
  });
}
