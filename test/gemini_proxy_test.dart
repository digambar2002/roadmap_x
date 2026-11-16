import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:roadmap_x/core/ai/ai_rate_limiter.dart';
import 'package:roadmap_x/core/ai/gemini_rest_client.dart';
import 'package:roadmap_x/core/ai/gemini_service.dart';

void main() {
  final proxy = Uri.parse('https://proj.supabase.co/functions/v1/gemini');

  test('Premium calls go to the app server with the session, not to Google',
      () async {
    late http.Request sent;
    final client = GeminiRestClient(
      apiKey: '',
      proxyUrl: proxy,
      authToken: () async => 'SESSION',
      client: MockClient((req) async {
        sent = req;
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': '{"ok":true}'},
                  ],
                },
              },
            ],
          })),
          200,
        );
      }),
    );
    final out =
        await client.generateJson(model: 'gemini-3.8-flash', prompt: 'hi');
    expect(out, '{"ok":true}');
    expect(sent.url, proxy);
    expect(sent.headers['Authorization'], 'Bearer SESSION');
    expect(sent.headers.containsKey('x-goog-api-key'), isFalse,
        reason: 'no key ever leaves the app');
    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    expect(body['model'], 'gemini-3.8-flash');
    expect((body['request'] as Map)['contents'], isA<List>());
  });

  test('no session means a clear sign-in error, without a request', () async {
    var called = false;
    final client = GeminiRestClient(
      apiKey: '',
      proxyUrl: proxy,
      authToken: () async => null,
      client: MockClient((_) async {
        called = true;
        return http.Response('', 200);
      }),
    );
    await expectLater(
      client.generateJson(model: 'm', prompt: 'p'),
      throwsA(isA<GeminiApiException>()
          .having((e) => e.status, 'status', 'UNAUTHENTICATED')),
    );
    expect(called, isFalse);
  });

  test("the server's daily cap reads as a rate limit", () async {
    final client = GeminiRestClient(
      apiKey: '',
      proxyUrl: proxy,
      authToken: () async => 'SESSION',
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'error': {
                'code': 429,
                'status': 'RESOURCE_EXHAUSTED',
                'message': 'Daily AI limit of 60 requests reached.',
              },
            }),
            429,
          )),
    );
    try {
      await client.generateJson(model: 'm', prompt: 'p');
      fail('should throw');
    } on GeminiApiException catch (e) {
      expect(classifyGeminiError(e), GeminiFailure.rateLimited);
    }
  });

  group('the server\'s own limits and gaps read clearly', () {
    GeminiService viaProxy(int code, String status, String message,
            {String? quotaId}) =>
        GeminiService(
          apiKey: '',
          model: 'gemini-3.8-flash',
          api: GeminiRestClient(
            apiKey: '',
            proxyUrl: proxy,
            authToken: () async => 'SESSION',
            client: MockClient((_) async => http.Response(
                  jsonEncode({
                    'error': {
                      'code': code,
                      'status': status,
                      'message': message,
                      'details': [
                        if (quotaId != null) {'quotaId': quotaId},
                      ],
                    },
                  }),
                  code,
                )),
          ),
        );

    setUp(AiRateLimiter.instance.reset);
    tearDown(AiRateLimiter.instance.reset);

    test('the free monthly allowance, without blocking the limiter', () async {
      final service = viaProxy(429, 'RESOURCE_EXHAUSTED', 'used',
          quotaId: 'RoadmapXFreePlansPerMonth');
      await expectLater(
        service.generateGoal('Learn to swim in two months'),
        throwsA(isA<GeminiException>().having(
          (e) => e.message,
          'message',
          allOf(contains('free AI plans'), contains('paste a plan'),
              isNot(contains('API key'))),
        )),
      );
      expect(AiRateLimiter.instance.blockReason(), isNull,
          reason: 'our cap is not Gemini\'s quota');
    });

    test('a function that is not deployed is not blamed on the model',
        () async {
      final service = viaProxy(404, 'NOT_FOUND', 'Function not found');
      await expectLater(
        service.generateGoal('Learn to swim in two months'),
        throwsA(
          isA<GeminiException>().having((e) => e.message, 'message',
              allOf(contains('paste a plan'), isNot(contains('model')))),
        ),
      );
    });

    test('an expired session asks to sign in, not for an API key', () async {
      final service = viaProxy(401, 'UNAUTHENTICATED', 'Session expired');
      await expectLater(
        service.generateGoal('Learn to swim in two months'),
        throwsA(
          isA<GeminiException>().having((e) => e.message, 'message',
              allOf(contains('Sign in again'), isNot(contains('API key')))),
        ),
      );
    });
  });
}
