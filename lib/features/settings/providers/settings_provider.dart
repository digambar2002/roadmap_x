import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/backup_service.dart';

// Settings keys
const _kUserName = 'user_name';
const _kThemeMode = 'theme_mode'; // 'dark'|'light'|'system'
const _kNonNeg0Label = 'non_neg_0_label';
const _kNonNeg1Label = 'non_neg_1_label';
const _kNonNeg2Label = 'non_neg_2_label';
const _kNonNeg3Label = 'non_neg_3_label';
const _kDailyReminderEnabled = 'daily_reminder_enabled';
const _kDailyReminderHour = 'daily_reminder_hour';
const _kDailyReminderMinute = 'daily_reminder_minute';
const _kTaskDueNotificationsEnabled = 'task_due_notifications_enabled';

class SettingsNotifier extends AsyncNotifier<SettingsState> {
  late SharedPreferences _prefs;

  @override
  Future<SettingsState> build() async {
    _prefs = await SharedPreferences.getInstance();
    return SettingsState(
      userName: _prefs.getString(_kUserName) ?? 'there',
      themeMode: _prefs.getString(_kThemeMode) ?? 'dark',
      dailyReminderEnabled: _prefs.getBool(_kDailyReminderEnabled) ?? false,
      dailyReminderHour: _prefs.getInt(_kDailyReminderHour) ?? 9,
      dailyReminderMinute: _prefs.getInt(_kDailyReminderMinute) ?? 0,
      taskDueNotificationsEnabled:
          _prefs.getBool(_kTaskDueNotificationsEnabled) ?? true,
      nonNegotiables: [
        _prefs.getString(_kNonNeg0Label) ?? 'Morning workout',
        _prefs.getString(_kNonNeg1Label) ?? 'Deep work block',
        _prefs.getString(_kNonNeg2Label) ?? 'Read 20 pages',
        _prefs.getString(_kNonNeg3Label) ?? 'Evening review',
      ],
    );
  }

  Future<void> setUserName(String name) async {
    await _prefs.setString(_kUserName, name);
    state = AsyncData(state.value!.copyWith(userName: name));
    await BackupService.instance.scheduleBackup();
  }

  Future<void> setThemeMode(String mode) async {
    await _prefs.setString(_kThemeMode, mode);
    state = AsyncData(state.value!.copyWith(themeMode: mode));
    await BackupService.instance.scheduleBackup();
  }

  Future<void> setDailyReminderEnabled(bool enabled) async {
    await _prefs.setBool(_kDailyReminderEnabled, enabled);
    state = AsyncData(state.value!.copyWith(dailyReminderEnabled: enabled));
    await BackupService.instance.scheduleBackup();
  }

  Future<void> setDailyReminderTime(int hour, int minute) async {
    await _prefs.setInt(_kDailyReminderHour, hour);
    await _prefs.setInt(_kDailyReminderMinute, minute);
    state = AsyncData(
      state.value!.copyWith(
        dailyReminderHour: hour,
        dailyReminderMinute: minute,
      ),
    );
  }

  Future<void> setTaskDueNotificationsEnabled(bool enabled) async {
    await _prefs.setBool(_kTaskDueNotificationsEnabled, enabled);
    state = AsyncData(
      state.value!.copyWith(taskDueNotificationsEnabled: enabled),
    );
  }

  Future<void> setNonNegotiable(int index, String label) async {
    final keys = [
      _kNonNeg0Label,
      _kNonNeg1Label,
      _kNonNeg2Label,
      _kNonNeg3Label
    ];
    await _prefs.setString(keys[index], label);
    final updated = List<String>.from(state.value!.nonNegotiables);
    updated[index] = label;
    state = AsyncData(state.value!.copyWith(nonNegotiables: updated));
    await BackupService.instance.scheduleBackup();
  }
}

class SettingsState {
  final String userName;
  final String themeMode;
  final bool dailyReminderEnabled;
  final int dailyReminderHour;
  final int dailyReminderMinute;
  final bool taskDueNotificationsEnabled;
  final List<String> nonNegotiables;

  const SettingsState({
    required this.userName,
    required this.themeMode,
    required this.dailyReminderEnabled,
    required this.dailyReminderHour,
    required this.dailyReminderMinute,
    required this.taskDueNotificationsEnabled,
    required this.nonNegotiables,
  });

  SettingsState copyWith({
    String? userName,
    String? themeMode,
    bool? dailyReminderEnabled,
    int? dailyReminderHour,
    int? dailyReminderMinute,
    bool? taskDueNotificationsEnabled,
    List<String>? nonNegotiables,
  }) =>
      SettingsState(
        userName: userName ?? this.userName,
        themeMode: themeMode ?? this.themeMode,
        dailyReminderEnabled: dailyReminderEnabled ?? this.dailyReminderEnabled,
        dailyReminderHour: dailyReminderHour ?? this.dailyReminderHour,
        dailyReminderMinute: dailyReminderMinute ?? this.dailyReminderMinute,
        taskDueNotificationsEnabled:
            taskDueNotificationsEnabled ?? this.taskDueNotificationsEnabled,
        nonNegotiables: nonNegotiables ?? this.nonNegotiables,
      );
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);
