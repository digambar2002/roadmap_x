import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../features/settings/providers/ai_settings_provider.dart';
import 'gemini_service.dart';

final geminiServiceProvider = Provider<GeminiService?>((ref) {
  final settings = ref.watch(aiSettingsNotifierProvider);
  final key = settings.apiKey;
  if (key == null || key.isEmpty) return null;

  return GeminiService(
    apiKey: key,
    model: settings.model,
  );
});
