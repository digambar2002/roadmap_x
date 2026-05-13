import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';
import '../models/models.dart';

/// Background callback for workmanager - must be a top-level function.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await NotificationService.instance.init();

      if (task == 'daily_reminder') {
        await NotificationService.instance._showDailyReminderNotification();
      } else if (task == 'schedule_event') {
        final label = inputData?['label'] ?? 'Event';
        final detail = inputData?['detail'] ?? '';
        await NotificationService.instance
            ._showEventNotification(label, detail);
      } else if (task == 'schedule_prior') {
        final label = inputData?['label'] ?? 'Event';
        await NotificationService.instance._showPriorNotification(label);
      }
      return true;
    } catch (e) {
      print('Workmanager task error: $e');
      return false;
    }
  });
}

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  static const _schedulePayloadPrefix = 'schedule:';

  Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    try {
      final tzName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzName));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('UTC'));
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    _initialized = true;
  }

  /// Initialize workmanager - call this in main.dart
  Future<void> initWorkmanager() async {
    await Workmanager().initialize(callbackDispatcher);
  }

  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final enabled = await android.areNotificationsEnabled();
      if (enabled ?? false) {
        await _requestExactAlarmPermission();
        return true;
      }
      final notifGranted =
          await android.requestNotificationsPermission() ?? false;
      if (notifGranted) {
        await _requestExactAlarmPermission();
      }
      return notifGranted;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return false;
  }

  Future<void> _requestExactAlarmPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      try {
        await android.requestExactAlarmsPermission();
      } catch (e) {
        print('Could not request exact alarm permission: $e');
      }
    }
  }

  /// Schedule daily reminder using workmanager (more reliable)
  Future<void> scheduleDailyReminder({
    required int hour,
    required int minute,
  }) async {
    if (!_initialized) {
      await init();
    }

    final granted = await requestPermission();
    if (!granted) return;

    // Cancel any existing daily reminders
    await Workmanager().cancelByTag('daily_reminder');

    // Schedule with workmanager for reliable delivery
    final timeOfDay = '$hour:${minute.toString().padLeft(2, '0')}';
    await Workmanager().registerPeriodicTask(
      'daily_reminder_${DateTime.now().millisecondsSinceEpoch}',
      'daily_reminder',
      tag: 'daily_reminder',
      frequency: const Duration(hours: 24),
      initialDelay: _calculateInitialDelay(hour, minute),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );

    print('Daily reminder scheduled for $timeOfDay via workmanager');
  }

  /// Show the daily reminder notification (called by workmanager or manually)
  Future<void> _showDailyReminderNotification() async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'daily_reminder',
        'Daily Reminder',
        channelDescription: 'Daily goal progress reminder',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    await _plugin.show(
      1,
      'RoadmapX Reminder',
      'Time to check on your goals! Keep the streak alive 🔥',
      details,
    );
  }

  Future<void> cancelDailyReminder() async {
    await Workmanager().cancelByTag('daily_reminder');
    await _plugin.cancel(1);
  }

  /// Sync schedule notifications - use workmanager as primary, fallback to zonedSchedule
  Future<void> syncScheduleNotifications(List<ScheduleItem> items) async {
    if (!_initialized) {
      await init();
    }

    final granted = await requestPermission();
    if (!granted) return;

    await _cancelScheduleNotifications();

    for (final item in items) {
      if (!item.isActive || item.weekdays.isEmpty) continue;

      final parsed = _parseTime(item.time);
      if (parsed == null) continue;

      for (final weekday in item.weekdays.toSet()) {
        final next = _nextWeekdayTime(
          weekday,
          parsed.$1,
          parsed.$2,
          from: tz.TZDateTime.now(tz.local),
        );

        final eventId = 2000000 + (item.id * 10) + weekday;
        final priorId = 3000000 + (item.id * 10) + weekday;
        await _scheduleViaZonedSchedule(eventId, priorId, item, next);
      }
    }
  }

  Future<void> _scheduleViaZonedSchedule(
    int eventId,
    int priorId,
    ScheduleItem item,
    tz.TZDateTime next,
  ) async {
    try {
      await _plugin.zonedSchedule(
        eventId,
        item.label,
        item.detail.isEmpty ? 'Scheduled event for now.' : item.detail,
        next,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'schedule_events',
            'Schedule Events',
            channelDescription: 'Notifications for scheduled routines/events',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: '$_schedulePayloadPrefix${item.id}:event',
        androidScheduleMode: AndroidScheduleMode.exact,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    } catch (e) {
      await _plugin.zonedSchedule(
        eventId,
        item.label,
        item.detail.isEmpty ? 'Scheduled event for now.' : item.detail,
        next,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'schedule_events',
            'Schedule Events',
            channelDescription: 'Notifications for scheduled routines/events',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: '$_schedulePayloadPrefix${item.id}:event',
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }

    final prior = next.subtract(const Duration(minutes: 5));
    if (!prior.isAfter(tz.TZDateTime.now(tz.local))) return;

    try {
      await _plugin.zonedSchedule(
        priorId,
        'Upcoming: ${item.label}',
        'Starts in 5 minutes',
        prior,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'schedule_prior',
            'Upcoming Event Alerts',
            channelDescription: '5-minute alerts before scheduled events',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: '$_schedulePayloadPrefix${item.id}:prior',
        androidScheduleMode: AndroidScheduleMode.exact,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    } catch (_) {
      await _plugin.zonedSchedule(
        priorId,
        'Upcoming: ${item.label}',
        'Starts in 5 minutes',
        prior,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'schedule_prior',
            'Upcoming Event Alerts',
            channelDescription: '5-minute alerts before scheduled events',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: '$_schedulePayloadPrefix${item.id}:prior',
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  /// Show event notification (called by workmanager or manually)
  Future<void> _showEventNotification(String label, String detail) async {
    const notifDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'schedule_events',
        'Schedule Events',
        channelDescription: 'Notifications for scheduled routines/events',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    // Use a random ID to avoid collisions
    final id = label.hashCode % 100000;
    await _plugin.show(id, label, detail, notifDetails);
  }

  /// Show prior notification (called by workmanager or manually)
  Future<void> _showPriorNotification(String label) async {
    const notifDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'schedule_prior',
        'Upcoming Event Alerts',
        channelDescription: '5-minute alerts before scheduled events',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    final id = (label.hashCode + 1) % 100000;
    await _plugin.show(
        id, 'Upcoming: $label', 'Starts in 5 minutes', notifDetails);
  }

  Future<void> _cancelScheduleNotifications() async {
    await Workmanager().cancelByTag('schedule_events');
    final pending = await _plugin.pendingNotificationRequests();
    for (final req in pending) {
      if (req.payload?.startsWith(_schedulePayloadPrefix) ?? false) {
        await _plugin.cancel(req.id);
      }
    }
  }

  (int, int)? _parseTime(String time) {
    try {
      final trimmed = time.trim();
      if (trimmed.isEmpty) return null;

      final normalized = trimmed
          .replaceAll('.', '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .toUpperCase();

      final amPm =
          RegExp(r'^(\d{1,2})[:.](\d{1,2})\s*([AP]M)$').firstMatch(normalized);
      if (amPm != null) {
        var h = int.parse(amPm.group(1)!);
        final m = int.parse(amPm.group(2)!);
        final p = amPm.group(3)!;
        if (h < 1 || h > 12 || m < 0 || m > 59) return null;
        if (p == 'PM' && h != 12) h += 12;
        if (p == 'AM' && h == 12) h = 0;
        return (h, m);
      }

      final twentyFour =
          RegExp(r'^(\d{1,2})[:.](\d{1,2})$').firstMatch(normalized);
      if (twentyFour != null) {
        final h = int.parse(twentyFour.group(1)!);
        final m = int.parse(twentyFour.group(2)!);
        if (h < 0 || h > 23 || m < 0 || m > 59) return null;
        return (h, m);
      }

      try {
        final dt = DateFormat.jm().parseLoose(trimmed);
        return (dt.hour, dt.minute);
      } catch (_) {}

      final dt24 = DateFormat.Hm().parseLoose(trimmed);
      return (dt24.hour, dt24.minute);
    } catch (_) {
      return null;
    }
  }

  tz.TZDateTime _nextWeekdayTime(
    int weekdaySun0,
    int hour,
    int minute, {
    required tz.TZDateTime from,
  }) {
    final nowWeekdaySun0 = from.weekday % 7;
    final diffDays = (weekdaySun0 - nowWeekdaySun0 + 7) % 7;

    var candidate = tz.TZDateTime(
      tz.local,
      from.year,
      from.month,
      from.day,
      hour,
      minute,
    ).add(Duration(days: diffDays));

    if (!candidate.isAfter(from)) {
      candidate = candidate.add(const Duration(days: 7));
    }

    return candidate;
  }

  Duration _calculateInitialDelay(int hour, int minute) {
    final now = DateTime.now();
    var scheduled = DateTime(now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled.difference(now);
  }

  /// Immediate notification for testing
  Future<void> showTestNotification() async {
    if (!_initialized) {
      await init();
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'test_channel',
        'Test Notifications',
        channelDescription: 'For testing notification delivery',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    await _plugin.show(
      999,
      'RoadmapX Test',
      'If you see this, notifications are working! 🎉',
      details,
    );
  }

  /// Scheduled test notification (workmanager)
  Future<void> showTestScheduledNotification() async {
    if (!_initialized) {
      await init();
    }

    final granted = await requestPermission();
    if (!granted) return;

    await Workmanager().registerOneOffTask(
      'test_scheduled_${DateTime.now().millisecondsSinceEpoch}',
      'schedule_event',
      inputData: {
        'label': 'RoadmapX Scheduled Test',
        'detail': 'This notification was scheduled 10 seconds ago.',
      },
      initialDelay: const Duration(seconds: 10),
    );
  }

  Future<void> cancelAll() => _plugin.cancelAll();
}
