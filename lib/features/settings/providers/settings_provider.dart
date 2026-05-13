import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Settings keys
const _kUserName = 'user_name';
const _kThemeMode = 'theme_mode'; // 'dark'|'light'|'system'
const _kNonNeg0Label = 'non_neg_0_label';
const _kNonNeg1Label = 'non_neg_1_label';
const _kNonNeg2Label = 'non_neg_2_label';
const _kNonNeg3Label = 'non_neg_3_label';
const _kDailyReminderEnabled = 'daily_reminder_enabled';

class SettingsNotifier extends AsyncNotifier<SettingsState> {
  late SharedPreferences _prefs;

  @override
  Future<SettingsState> build() async {
    _prefs = await SharedPreferences.getInstance();
    return SettingsState(
      userName: _prefs.getString(_kUserName) ?? 'there',
      themeMode: _prefs.getString(_kThemeMode) ?? 'dark',
      dailyReminderEnabled: _prefs.getBool(_kDailyReminderEnabled) ?? false,
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
  }

  Future<void> setThemeMode(String mode) async {
    await _prefs.setString(_kThemeMode, mode);
    state = AsyncData(state.value!.copyWith(themeMode: mode));
  }

  Future<void> setDailyReminderEnabled(bool enabled) async {
    await _prefs.setBool(_kDailyReminderEnabled, enabled);
    state = AsyncData(state.value!.copyWith(dailyReminderEnabled: enabled));
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
  }
}

class SettingsState {
  final String userName;
  final String themeMode;
  final bool dailyReminderEnabled;
  final List<String> nonNegotiables;

  const SettingsState({
    required this.userName,
    required this.themeMode,
    required this.dailyReminderEnabled,
    required this.nonNegotiables,
  });

  SettingsState copyWith({
    String? userName,
    String? themeMode,
    bool? dailyReminderEnabled,
    List<String>? nonNegotiables,
  }) =>
      SettingsState(
        userName: userName ?? this.userName,
        themeMode: themeMode ?? this.themeMode,
        dailyReminderEnabled: dailyReminderEnabled ?? this.dailyReminderEnabled,
        nonNegotiables: nonNegotiables ?? this.nonNegotiables,
      );
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);
