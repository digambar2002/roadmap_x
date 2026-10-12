import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';

/// Customization attributes for an individual habit.
class HabitCustomization {
  final int colorHex;
  final List<int> repeatDays; // 1=Mon, 2=Tue, ..., 7=Sun
  final String category; // 'Morning', 'Workload', 'Night', 'Anytime'
  final bool hasReminder;
  final int reminderHour;
  final int reminderMinute;

  const HabitCustomization({
    this.colorHex = 0xFF10B981,
    this.repeatDays = const [1, 2, 3, 4, 5, 6, 7],
    this.category = 'Morning',
    this.hasReminder = false,
    this.reminderHour = 9,
    this.reminderMinute = 0,
  });

  Color get color => Color(colorHex);

  String get repeatSummary {
    if (repeatDays.length == 7) return 'Everyday';
    if (repeatDays.length == 5 &&
        repeatDays.contains(1) &&
        repeatDays.contains(2) &&
        repeatDays.contains(3) &&
        repeatDays.contains(4) &&
        repeatDays.contains(5)) {
      return 'Weekdays';
    }
    if (repeatDays.length == 2 &&
        repeatDays.contains(6) &&
        repeatDays.contains(7)) {
      return 'Weekends';
    }
    const dayNames = {1: 'M', 2: 'T', 3: 'W', 4: 'T', 5: 'F', 6: 'S', 7: 'S'};
    return repeatDays.map((d) => dayNames[d] ?? '').join(' ');
  }

  String get reminderFormatted {
    if (!hasReminder) return '';
    final hour = reminderHour % 12 == 0 ? 12 : reminderHour % 12;
    final minute = reminderMinute.toString().padLeft(2, '0');
    final period = reminderHour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  bool isScheduledForWeekday(int weekday) {
    return repeatDays.contains(weekday);
  }

  Map<String, dynamic> toJson() => {
        'colorHex': colorHex,
        'repeatDays': repeatDays,
        'category': category,
        'hasReminder': hasReminder,
        'reminderHour': reminderHour,
        'reminderMinute': reminderMinute,
      };

  factory HabitCustomization.fromJson(Map<String, dynamic> json) {
    return HabitCustomization(
      colorHex: json['colorHex'] as int? ?? 0xFF10B981,
      repeatDays: (json['repeatDays'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          const [1, 2, 3, 4, 5, 6, 7],
      category: json['category'] as String? ?? 'Morning',
      hasReminder: json['hasReminder'] as bool? ?? false,
      reminderHour: json['reminderHour'] as int? ?? 9,
      reminderMinute: json['reminderMinute'] as int? ?? 0,
    );
  }

  HabitCustomization copyWith({
    int? colorHex,
    List<int>? repeatDays,
    String? category,
    bool? hasReminder,
    int? reminderHour,
    int? reminderMinute,
  }) {
    return HabitCustomization(
      colorHex: colorHex ?? this.colorHex,
      repeatDays: repeatDays ?? this.repeatDays,
      category: category ?? this.category,
      hasReminder: hasReminder ?? this.hasReminder,
      reminderHour: reminderHour ?? this.reminderHour,
      reminderMinute: reminderMinute ?? this.reminderMinute,
    );
  }

  static const List<int> presetColors = [
    0xFF10B981, // Emerald Green
    0xFF3B82F6, // Electric Blue
    0xFF8B5CF6, // Vivid Violet
    0xFFF59E0B, // Sunny Amber
    0xFFEC4899, // Hot Pink
    0xFFF97316, // Vibrant Orange
    0xFF06B6D4, // Aqua Cyan
    0xFF14B8A6, // Forest Teal
    0xFF6366F1, // Deep Indigo
    0xFFEF4444, // Bright Red
  ];

  static const List<String> presetCategories = [
    'Morning',
    'Workload',
    'Night',
    'Anytime',
  ];
}

class HabitCustomizationService {
  HabitCustomizationService._();
  static final HabitCustomizationService instance =
      HabitCustomizationService._();

  static const _prefix = 'habit_meta_';

  Future<HabitCustomization> get(String habitUid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$habitUid');
    if (raw == null) return const HabitCustomization();
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return HabitCustomization.fromJson(map);
    } catch (_) {
      return const HabitCustomization();
    }
  }

  Future<void> save(
    String habitUid,
    HabitCustomization customization, {
    String? habitLabel,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_prefix$habitUid',
      jsonEncode(customization.toJson()),
    );

    // Sync notification
    if (customization.hasReminder) {
      await NotificationService.instance.scheduleHabitReminder(
        habitUid: habitUid,
        habitLabel: habitLabel ?? 'Daily Habit',
        hour: customization.reminderHour,
        minute: customization.reminderMinute,
        repeatDays: customization.repeatDays,
      );
    } else {
      await NotificationService.instance.cancelHabitReminder(habitUid);
    }
  }

  Future<void> delete(String habitUid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$habitUid');
    await NotificationService.instance.cancelHabitReminder(habitUid);
  }
}

final habitCustomizationProvider =
    FutureProvider.family<HabitCustomization, String>((ref, habitUid) async {
  return HabitCustomizationService.instance.get(habitUid);
});

final habitCustomizationVersionProvider = StateProvider<int>((_) => 0);
