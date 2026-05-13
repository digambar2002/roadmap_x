import 'package:shared_preferences/shared_preferences.dart';

class AiSettingsRepository {
  static const _keyApiKey = 'gemini_api_key';
  static const _keyModel = 'gemini_model';
  static const _defaultModel = 'gemini-2.5-flash';
  static const _allowedModels = {
    'gemini-2.5-flash',
    'gemini-2.5-pro',
  };

  final SharedPreferences _prefs;
  AiSettingsRepository(this._prefs);

  Future<void> saveApiKey(String key) async {
    await _prefs.setString(_keyApiKey, key.trim());
  }

  Future<void> saveModel(String model) async {
    await _prefs.setString(_keyModel, model);
  }

  String? getApiKey() => _prefs.getString(_keyApiKey);

  String getModel() {
    final model = _prefs.getString(_keyModel);
    if (model == null || !_allowedModels.contains(model)) {
      return _defaultModel;
    }
    return model;
  }

  bool get hasApiKey {
    final key = getApiKey();
    return key != null && key.isNotEmpty;
  }

  Future<void> clearApiKey() async {
    await _prefs.remove(_keyApiKey);
  }
}
