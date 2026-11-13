import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../features/settings/providers/ai_settings_provider.dart';
import 'ai_access.dart';
import 'gemini_service.dart';

/// Goal planning and "Organise with AI". Uses the user's own key when they
/// have one, otherwise the Premium server route; null when neither applies.
final geminiServiceProvider = Provider<GeminiService?>((ref) {
  final api = ref.watch(geminiRestClientProvider);
  if (api == null) return null;
  return GeminiService(
    apiKey: api.apiKey,
    model: ref.watch(aiSettingsNotifierProvider).model,
    api: api,
  );
});
