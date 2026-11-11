import 'package:flutter_test/flutter_test.dart';
import 'package:roadmap_x/core/ai/ai_rate_limiter.dart';

void main() {
  final limiter = AiRateLimiter.instance;
  late DateTime clock;

  setUp(() {
    limiter.reset();
    clock = DateTime(2026, 11, 11, 10);
    limiter.now = () => clock;
  });
  tearDown(limiter.reset);

  test('paces the app below the free per-minute limit', () {
    for (var i = 0; i < AiRateLimiter.maxPerMinute; i++) {
      expect(limiter.blockReason(), isNull);
      limiter.record();
    }
    expect(limiter.blockReason(), contains('Too many AI requests'));
    clock = clock.add(const Duration(seconds: 61));
    expect(limiter.blockReason(), isNull, reason: 'the minute has passed');
  });

  test('waits as long as Gemini asks after a 429', () {
    final kind = limiter.onRateLimited(
      '429 Resource has been exhausted. Please retry in 37.2s.',
      model: AiRateLimiter.freeModel,
    );
    expect(kind, RateLimitKind.perMinute);
    expect(limiter.blockReason(), contains('slow down'));
    clock = clock.add(const Duration(seconds: 30));
    expect(limiter.blockReason(), isNotNull, reason: 'still inside the wait');
    clock = clock.add(const Duration(seconds: 10));
    expect(limiter.blockReason(), isNull);
  });

  test('understands the retryDelay field too', () {
    limiter.onRateLimited('{"retryDelay": "12s"} quota exceeded',
        model: AiRateLimiter.freeModel);
    clock = clock.add(const Duration(seconds: 10));
    expect(limiter.blockReason(), isNotNull);
    clock = clock.add(const Duration(seconds: 4));
    expect(limiter.blockReason(), isNull);
  });

  test('a spent daily quota blocks until the Pacific-midnight reset', () {
    final kind = limiter.onRateLimited(
      'Quota exceeded for metric: generate_content_free_tier_requests, '
      'limit: 20, quotaId: GenerateRequestsPerDayPerProjectPerModel-FreeTier',
      model: AiRateLimiter.freeModel,
    );
    expect(kind, RateLimitKind.daily);
    expect(limiter.blockReason(), contains('free Gemini limit is used up'));
    // Resets at the next 08:00 UTC (midnight Pacific), whatever the local
    // time zone is.
    final utc = clock.toUtc();
    var reset = DateTime.utc(utc.year, utc.month, utc.day, 8);
    if (!reset.isAfter(utc)) reset = reset.add(const Duration(days: 1));
    clock = reset.toLocal().subtract(const Duration(minutes: 1));
    expect(limiter.blockReason(), isNotNull);
    clock = reset.toLocal().add(const Duration(minutes: 1));
    expect(limiter.blockReason(), isNull);
  });

  test('a model with no free quota falls back to Flash for the session', () {
    const pro = 'gemini-3.1-pro-preview';
    expect(limiter.modelFor(pro), pro);
    final kind = limiter.onRateLimited(
      'Quota exceeded for metric: generate_content_free_tier_requests, '
      'limit: 0, model: gemini-3.1-pro',
      model: pro,
    );
    expect(kind, RateLimitKind.modelNotFree);
    expect(limiter.modelFor(pro), AiRateLimiter.freeModel);
    expect(limiter.blockReason(), isNull,
        reason: 'Flash can still be used right away');
  });

  test('recognises rate-limit errors', () {
    expect(isRateLimitError('429 Too Many Requests'), isTrue);
    expect(isRateLimitError('RESOURCE_EXHAUSTED'), isTrue);
    expect(isRateLimitError('API key not valid'), isFalse);
  });
}
