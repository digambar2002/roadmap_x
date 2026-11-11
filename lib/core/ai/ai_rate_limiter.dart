/// One gate in front of every Gemini request in the app.
///
/// The free Gemini tier is small (for Flash, roughly 5 requests a minute and
/// a couple of dozen a day; preview Pro models get none at all). Hitting it
/// used to make things worse: the app retried a rate-limited request after
/// two seconds, spending another request, and pull-to-refresh forced a fresh
/// briefing every time. This class:
///
/// - paces requests from the app below the free per-minute limit,
/// - honours the wait Google asks for after a "too many requests" reply,
/// - stops asking for the rest of the day once the daily quota is spent,
/// - remembers when a model has no free quota, so callers switch to Flash.
class AiRateLimiter {
  AiRateLimiter._();
  static final AiRateLimiter instance = AiRateLimiter._();

  /// The model every free key can use; the fallback when another has no quota.
  static const freeModel = 'gemini-3.8-flash';

  /// One under the free tier's 5 per minute, so background and foreground
  /// requests together stay inside it.
  static const maxPerMinute = 4;

  final _recent = <DateTime>[];
  DateTime? _blockedUntil;
  bool _dailyLimit = false;
  final _modelsWithoutQuota = <String>{};

  DateTime Function() now = DateTime.now;

  /// The model to actually call: [preferred], unless it has turned out to
  /// have no quota on this key.
  String modelFor(String preferred) =>
      _modelsWithoutQuota.contains(preferred) ? freeModel : preferred;

  /// Null when a request may go out now; otherwise why not, for the user.
  String? blockReason() {
    final t = now();
    final until = _blockedUntil;
    if (until != null && t.isBefore(until)) {
      if (_dailyLimit) {
        return 'Today\'s free Gemini limit is used up. It resets in '
            '${_humanise(until.difference(t))}. A paid API key removes the limit.';
      }
      return 'Gemini asked us to slow down. Try again in '
          '${_humanise(until.difference(t))}.';
    }
    _recent.removeWhere((r) => t.difference(r) >= const Duration(minutes: 1));
    if (_recent.length >= maxPerMinute) {
      final wait = const Duration(minutes: 1) - t.difference(_recent.first);
      return 'Too many AI requests in a minute. Try again in '
          '${_humanise(wait)}.';
    }
    return null;
  }

  /// Call right before sending a request.
  void record() => _recent.add(now());

  /// What a "429 / resource exhausted" reply means, and the wait it implies.
  RateLimitKind onRateLimited(String error, {required String model}) {
    final text = error.toLowerCase();

    // "limit: 0" — this model is not on the free tier at all.
    if (RegExp(r'limit:\s*0\b').hasMatch(text) ||
        RegExp(r'"quotavalue"\s*:\s*"0"').hasMatch(text)) {
      if (model != freeModel) _modelsWithoutQuota.add(model);
      return RateLimitKind.modelNotFree;
    }

    final t = now();
    if (text.contains('perday') ||
        text.contains('per day') ||
        text.contains('requests_per_day') ||
        text.contains('daily')) {
      // Gemini's daily quotas reset at midnight Pacific time.
      _dailyLimit = true;
      _blockedUntil = _nextPacificMidnight(t);
      return RateLimitKind.daily;
    }

    _dailyLimit = false;
    _blockedUntil = t.add(_retryDelay(text) ?? const Duration(seconds: 60));
    return RateLimitKind.perMinute;
  }

  /// The user-facing message for a rate-limit reply.
  String messageFor(RateLimitKind kind) => switch (kind) {
        RateLimitKind.modelNotFree =>
          'This Gemini model isn\'t included in the free tier. Switching to '
              'Gemini 3.8 Flash — or use a paid API key for Pro.',
        _ => blockReason() ?? 'Gemini is busy. Try again in a minute.',
      };

  /// "Please retry in 37.2s" or `"retryDelay": "37s"`.
  static Duration? _retryDelay(String text) {
    final m = RegExp(r'retry(?:\s+in|\s+after|delay"?\s*:\s*"?)\s*([\d.]+)\s*s')
        .firstMatch(text);
    if (m == null) return null;
    final seconds = double.tryParse(m.group(1)!);
    if (seconds == null) return null;
    return Duration(milliseconds: (seconds * 1000).ceil() + 1000);
  }

  static DateTime _nextPacificMidnight(DateTime local) {
    // Pacific is UTC-8 (UTC-7 in summer); 08:00 UTC is the later of the two,
    // so waiting until then never retries too early.
    final utc = local.toUtc();
    var reset = DateTime.utc(utc.year, utc.month, utc.day, 8);
    if (!reset.isAfter(utc)) reset = reset.add(const Duration(days: 1));
    return reset.toLocal();
  }

  static String _humanise(Duration d) {
    if (d.inHours >= 1) {
      final m = d.inMinutes % 60;
      return '${d.inHours} h${m > 0 ? ' $m min' : ''}';
    }
    if (d.inMinutes >= 1)
      return '${d.inMinutes + (d.inSeconds % 60 > 0 ? 1 : 0)} min';
    return '${d.inSeconds.clamp(1, 59)} s';
  }

  /// For tests.
  void reset() {
    _recent.clear();
    _blockedUntil = null;
    _dailyLimit = false;
    _modelsWithoutQuota.clear();
    now = DateTime.now;
  }
}

enum RateLimitKind { perMinute, daily, modelNotFree }

/// Whether an SDK error is a rate-limit / quota reply.
bool isRateLimitError(String error) {
  final t = error.toLowerCase();
  return t.contains('429') ||
      t.contains('resource_exhausted') ||
      t.contains('resource has been exhausted') ||
      t.contains('quota') ||
      t.contains('rate limit') ||
      t.contains('too many requests');
}
