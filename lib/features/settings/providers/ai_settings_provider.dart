import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/services/shared_preferences_provider.dart';
import '../data/ai_settings_repository.dart';

typedef AiSettingsState = ({String? apiKey, String model});

final aiSettingsRepositoryProvider = Provider<AiSettingsRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return AiSettingsRepository(prefs);
});

class AiSettingsNotifier extends Notifier<AiSettingsState> {
  @override
  AiSettingsState build() {
    final repo = ref.watch(aiSettingsRepositoryProvider);
    return (apiKey: repo.getApiKey(), model: repo.getModel());
  }

  Future<void> saveApiKey(String key) async {
    await ref.read(aiSettingsRepositoryProvider).saveApiKey(key);
    ref.invalidateSelf();
  }

  Future<void> saveModel(String model) async {
    await ref.read(aiSettingsRepositoryProvider).saveModel(model);
    ref.invalidateSelf();
  }

  Future<void> clearApiKey() async {
    await ref.read(aiSettingsRepositoryProvider).clearApiKey();
    ref.invalidateSelf();
  }
}

final aiSettingsNotifierProvider = NotifierProvider<AiSettingsNotifier, AiSettingsState>(
  AiSettingsNotifier.new,
);
