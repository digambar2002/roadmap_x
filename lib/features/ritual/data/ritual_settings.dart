import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/notification_service.dart';

/// When the morning and evening ritual reminders fire. On by default: they
/// are what turns the rituals into a daily habit, and each can be switched
/// off or moved in Settings.
class RitualSettings {
  const RitualSettings._();

  static const _morningOn = 'ritual_morning_enabled';
  static const _morningAt = 'ritual_morning_minutes';
  static const _eveningOn = 'ritual_evening_enabled';
  static const _eveningAt = 'ritual_evening_minutes';

  static bool morningEnabled(SharedPreferences p) =>
      p.getBool(_morningOn) ?? true;
  static bool eveningEnabled(SharedPreferences p) =>
      p.getBool(_eveningOn) ?? true;

  /// Minutes after midnight.
  static int morningAt(SharedPreferences p) => p.getInt(_morningAt) ?? 8 * 60;
  static int eveningAt(SharedPreferences p) => p.getInt(_eveningAt) ?? 21 * 60;

  static Future<void> setMorning(SharedPreferences p,
      {bool? enabled, int? minutes}) async {
    if (enabled != null) await p.setBool(_morningOn, enabled);
    if (minutes != null) await p.setInt(_morningAt, minutes);
    await sync(p);
  }

  static Future<void> setEvening(SharedPreferences p,
      {bool? enabled, int? minutes}) async {
    if (enabled != null) await p.setBool(_eveningOn, enabled);
    if (minutes != null) await p.setInt(_eveningAt, minutes);
    await sync(p);
  }

  static Future<void> sync(SharedPreferences p) {
    ({int hour, int minute}) hm(int m) => (hour: m ~/ 60, minute: m % 60);
    return NotificationService.instance.scheduleRituals(
      morning: morningEnabled(p) ? hm(morningAt(p)) : null,
      evening: eveningEnabled(p) ? hm(eveningAt(p)) : null,
    );
  }
}
