import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../features/premium/providers/premium_provider.dart';
import '../../features/settings/providers/ai_settings_provider.dart';
import '../sync/account_service.dart';
import '../sync/sync_config.dart';
import 'gemini_rest_client.dart';

/// How this user gets AI, if at all.
enum AiAccess {
  /// No AI: free account without a key of their own.
  none,

  /// The user entered their own Gemini key; calls go straight to Google.
  ownKey,

  /// Premium: calls go through the app's server, which holds the key.
  premium,
}

/// Your own key wins when present (it is free to you and has your own
/// quota). Otherwise Premium accounts use the server route, so customers
/// never need to create a Google API key.
final aiAccessProvider = Provider<AiAccess>((ref) {
  final key = ref.watch(aiSettingsNotifierProvider).apiKey;
  if (key != null && key.isNotEmpty) return AiAccess.ownKey;
  final account = ref.watch(accountProvider).valueOrNull;
  final signedIn =
      account?.isSignedIn ?? AccountService.instance.state.isSignedIn;
  if (SyncConfig.isConfigured && signedIn && ref.watch(isPremiumProvider)) {
    return AiAccess.premium;
  }
  return AiAccess.none;
});

/// The Gemini client for the current access, or null with no AI.
final geminiRestClientProvider = Provider<GeminiRestClient?>((ref) {
  switch (ref.watch(aiAccessProvider)) {
    case AiAccess.none:
      return null;
    case AiAccess.ownKey:
      return GeminiRestClient(
          apiKey: ref.watch(aiSettingsNotifierProvider).apiKey!);
    case AiAccess.premium:
      return GeminiRestClient(
        apiKey: '',
        proxyUrl: Uri.parse('${SyncConfig.supabaseUrl}/functions/v1/gemini'),
        authToken: () async =>
            AccountService.instance.client.auth.currentSession?.accessToken,
      );
  }
});
