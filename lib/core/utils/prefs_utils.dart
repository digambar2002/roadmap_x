import 'package:shared_preferences/shared_preferences.dart';

class PrefsUtils {
  PrefsUtils._();

  static bool parseBool(dynamic value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is int) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
    return fallback;
  }

  static bool readBool(SharedPreferences prefs, String key, {bool fallback = false}) {
    if (!prefs.containsKey(key)) return fallback;
    try {
      return prefs.getBool(key) ?? fallback;
    } catch (_) {
      return parseBool(prefs.get(key), fallback: fallback);
    }
  }
}
