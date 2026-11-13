import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:roadmap_x/core/ai/gemini_rest_client.dart';

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
}
