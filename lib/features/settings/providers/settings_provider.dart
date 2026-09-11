import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/local_changes.dart';
import '../../../core/services/synced_settings.dart';

// Settings keys
const _kUserName = 'user_name';
const _kThemeMode = 'theme_mode'; // 'dark'|'light'|'system'
const _kDailyReminderEnabled = 'daily_reminder_enabled';
const _kDailyReminderHour = 'daily_reminder_hour';
const _kDailyReminderMinute = 'daily_reminder_minute';
const _kTaskDueNotificationsEnabled = 'task_due_notifications_enabled';

class SettingsNotifier extends AsyncNotifier<SettingsState> {
  late SharedPreferences _prefs;

  @override
  Future<SettingsState> build() async {
    _prefs = await SharedPreferences.getInstance();

    // A setting merged in from another device lands in SharedPreferences
    // behind this notifier's back, so re-read when that happens.
    final sub = SyncedSettings.instance.changes.listen((_) {
      ref.invalidateSelf();
    });
    ref.onDispose(sub.cancel);

    return SettingsState(
      userName: _prefs.getString(_kUserName) ?? 'there',
      themeMode: _prefs.getString(_kThemeMode) ?? 'dark',
      dailyReminderEnabled: _prefs.getBool(_kDailyReminderEnabled) ?? false,
      dailyReminderHour: _prefs.getInt(_kDailyReminderHour) ?? 9,
      dailyReminderMinute: _prefs.getInt(_kDailyReminderMinute) ?? 0,
      taskDueNotificationsEnabled:
          _prefs.getBool(_kTaskDueNotificationsEnabled) ?? true,
    );
  }

  Future<void> setUserName(String name) async {
    final current = state.valueOrNull;
    if (current == null) return;
    await _prefs.setString(_kUserName, name);
    await SyncedSettings.instance.capture(_prefs, _kUserName);
    state = AsyncData(current.copyWith(userName: name));
    await LocalChanges.instance.notify();
  }

  Future<void> setThemeMode(String mode) async {
    final current = state.valueOrNull;
    if (current == null) return;
    await _prefs.setString(_kThemeMode, mode);
    state = AsyncData(current.copyWith(themeMode: mode));
    await LocalChanges.instance.notify();
  }

  Future<void> setDailyReminderEnabled(bool enabled) async {
    final current = state.valueOrNull;
    if (current == null) return;
    await _prefs.setBool(_kDailyReminderEnabled, enabled);
    state = AsyncData(current.copyWith(dailyReminderEnabled: enabled));
    await LocalChanges.instance.notify();
  }

  Future<void> setDailyReminderTime(int hour, int minute) async {
    final current = state.valueOrNull;
    if (current == null) return;
    await _prefs.setInt(_kDailyReminderHour, hour);
    await _prefs.setInt(_kDailyReminderMinute, minute);
    state = AsyncData(
      current.copyWith(
        dailyReminderHour: hour,
        dailyReminderMinute: minute,
      ),
    );
    await LocalChanges.instance.notify();
  }

  Future<void> setTaskDueNotificationsEnabled(bool enabled) async {
    final current = state.valueOrNull;
    if (current == null) return;
    await _prefs.setBool(_kTaskDueNotificationsEnabled, enabled);
    state = AsyncData(
      current.copyWith(taskDueNotificationsEnabled: enabled),
    );
    await LocalChanges.instance.notify();
  }
}

class SettingsState {
  final String userName;
  final String themeMode;
  final bool dailyReminderEnabled;
  final int dailyReminderHour;
  final int dailyReminderMinute;
  final bool taskDueNotificationsEnabled;

  const SettingsState({
    required this.userName,
    required this.themeMode,
    required this.dailyReminderEnabled,
    required this.dailyReminderHour,
    required this.dailyReminderMinute,
    required this.taskDueNotificationsEnabled,
  });

  SettingsState copyWith({
    String? userName,
    String? themeMode,
    bool? dailyReminderEnabled,
    int? dailyReminderHour,
    int? dailyReminderMinute,
    bool? taskDueNotificationsEnabled,
  }) =>
      SettingsState(
        userName: userName ?? this.userName,
        themeMode: themeMode ?? this.themeMode,
        dailyReminderEnabled: dailyReminderEnabled ?? this.dailyReminderEnabled,
        dailyReminderHour: dailyReminderHour ?? this.dailyReminderHour,
        dailyReminderMinute: dailyReminderMinute ?? this.dailyReminderMinute,
        taskDueNotificationsEnabled:
            taskDueNotificationsEnabled ?? this.taskDueNotificationsEnabled,
      );
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);
