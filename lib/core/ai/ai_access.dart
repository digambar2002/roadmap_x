import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../features/premium/providers/premium_provider.dart';
import '../../features/settings/providers/ai_settings_provider.dart';
import '../subscription/entitlements.dart';
import '../sync/account_service.dart';
import '../sync/sync_config.dart';
import 'gemini_rest_client.dart';

/// How this user gets AI, if at all.
enum AiAccess {
  /// No AI: not signed in, and no key of their own.
  none,

  /// The user entered their own Gemini key; calls go straight to Google.
  ownKey,

  /// Signed in on the free plan: a few AI-built plans a month through the
  /// app's server. Enough to try the app's best feature; the coach
  /// (briefings, reviews, chat) stays with Premium.
  free,

  /// Premium: calls go through the app's server, which holds the key.
  premium,
}

/// Your own key wins when present (it is free to you and has your own
/// quota). Otherwise signed-in accounts use the server route, so nobody
/// needs to create a Google API key to get a plan built.
final aiAccessProvider = Provider<AiAccess>((ref) {
  final key = ref.watch(aiSettingsNotifierProvider).apiKey;
  if (key != null && key.isNotEmpty) return AiAccess.ownKey;
  final account = ref.watch(accountProvider).valueOrNull;
  final signedIn =
      account?.isSignedIn ?? AccountService.instance.state.isSignedIn;
  if (SyncConfig.isConfigured && signedIn) {
    return ref.watch(isPremiumProvider) ? AiAccess.premium : AiAccess.free;
  }
  return AiAccess.none;
});

/// Whether AI can build a plan for this user at all (any access but none).
final canUseAiPlansProvider = Provider<bool>(
  (ref) => ref.watch(aiAccessProvider) != AiAccess.none,
);

/// Free AI plans left this month, or null when the user isn't on the free
/// allowance (own key, Premium, signed out) or the count can't be fetched.
final freeAiPlansLeftProvider = FutureProvider<int?>((ref) async {
  if (ref.watch(aiAccessProvider) != AiAccess.free) return null;
  try {
    final used = await AccountService.instance.client
        .rpc('ai_requests_this_month')
        .timeout(const Duration(seconds: 8));
    if (used is! int) return null;
    return (Entitlements.freeAiPlansPerMonth - used)
        .clamp(0, Entitlements.freeAiPlansPerMonth);
  } catch (_) {
    // Offline, or the server hasn't been updated yet. The server still
    // enforces the limit; we just can't show the count.
    return null;
  }
});

/// The Gemini client for the current access, or null with no AI.
final geminiRestClientProvider = Provider<GeminiRestClient?>((ref) {
  switch (ref.watch(aiAccessProvider)) {
    case AiAccess.none:
      return null;
    case AiAccess.ownKey:
      return GeminiRestClient(
          apiKey: ref.watch(aiSettingsNotifierProvider).apiKey!);
    case AiAccess.free:
    case AiAccess.premium:
      return GeminiRestClient(
        apiKey: '',
        proxyUrl: Uri.parse('${SyncConfig.supabaseUrl}/functions/v1/gemini'),
        authToken: () async =>
            AccountService.instance.client.auth.currentSession?.accessToken,
      );
  }
});
