import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';
import '../db/isar_service.dart';
import '../models/models.dart';
import 'backup_service.dart';

/// Background callback for workmanager - must be a top-level function.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await IsarService.instance.init();
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
      } else if (task == 'auto_backup') {
        await BackupService.instance.performAutoBackup();
      }
      return true;
    } catch (e) {
      debugPrint('Workmanager task error: $e');
      return false;
    }
  });
}

/// Called by the plugin when a notification is tapped while the app is
/// terminated or in the background. Must be a top-level function.
@pragma('vm:entry-point')
void _onBackgroundNotificationResponse(NotificationResponse response) {
  // Nothing to do here: the payload is re-read on the next launch through
  // getNotificationAppLaunchDetails() and routed by the app.
}

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  static const _schedulePayloadPrefix = 'schedule:';
  static const _taskDuePayloadPrefix = 'task_due:';
  static const _habitPayloadPrefix = 'habit:';
  static const _dailyReminderPayload = 'daily_reminder';
  static const _dailyReminderId = 1;
  static const _companionNudgeId = 5;
  static const _morningPlanId = 6;
  static const _eveningWrapId = 7;
  static const _focusEndId = 8;
  static const _focusPayload = 'focus';
  static const _planPayload = 'ritual_plan';
  static const _wrapPayload = 'ritual_wrap';
  static const _companionPayload = 'companion';
  static const _testNotificationId = 999;
  static const _testScheduledNotificationId = 998;

  /// Emits the payload of a notification the user tapped, so the app can
  /// navigate to the matching screen.
  final _tapController = StreamController<String>.broadcast();
  Stream<String> get onNotificationTapped => _tapController.stream;

  static bool supportsNotificationsFor(TargetPlatform platform) =>
      platform == TargetPlatform.android ||
      platform == TargetPlatform.iOS ||
      platform == TargetPlatform.macOS;

  static bool get _supportsNotifications =>
      supportsNotificationsFor(defaultTargetPlatform);

  /// True where background scheduling is actually available. Workmanager ships
  /// Android and iOS implementations only; calling it on desktop throws a
  /// MissingPluginException.
  static bool get _supportsWorkmanager =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  IOSFlutterLocalNotificationsPlugin? get _ios =>
      _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

  MacOSFlutterLocalNotificationsPlugin? get _macOS =>
      _plugin.resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin>();

  Future<void> init() async {
    if (_initialized) return;
    if (!_supportsNotifications) {
      _initialized = true;
      return;
    }

    tz.initializeTimeZones();
    try {
      final tzName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzName));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('UTC'));
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    // macOS needs its own settings object. Omitting it does not degrade
    // gracefully — the plugin throws, and since init() is awaited from main()
    // the app never reaches runApp and shows no window at all.
    await _plugin.initialize(
      const InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _tapController.add(payload);
        }
      },
      onDidReceiveBackgroundNotificationResponse:
          _onBackgroundNotificationResponse,
    );

    final androidPlugin = _android;
    if (androidPlugin != null) {
      final channels = [
        const AndroidNotificationChannel(
          'habit_reminders',
          'Habit Reminders',
          description: 'Reminders for daily habits',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        ),
        const AndroidNotificationChannel(
          'daily_reminder',
          'Daily Reminder',
          description: 'Daily goal progress reminder',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        ),
        const AndroidNotificationChannel(
          'schedule_events',
          'Schedule Events',
          description: 'Notifications for scheduled routines/events',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        ),
        const AndroidNotificationChannel(
          'schedule_prior',
          'Upcoming Event Alerts',
          description: '5-minute alerts before scheduled events',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        ),
        const AndroidNotificationChannel(
          'task_due',
          'Task Due',
          description: 'Task due date reminders',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        ),
        const AndroidNotificationChannel(
          'companion',
          'Companion',
          description: 'Reminders when your pet needs looking after',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        ),
        const AndroidNotificationChannel(
          'test_channel',
          'Test Notifications',
          description: 'For testing notification delivery',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        ),
      ];
      for (final channel in channels) {
        await androidPlugin.createNotificationChannel(channel);
      }
    }

    _initialized = true;
  }

  /// Payload of the notification that launched the app, if any. Consumed by
  /// the app once at startup to route to the right screen.
  Future<String?> consumeLaunchPayload() async {
    if (!_supportsNotifications) return null;
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp ?? false) {
        return details!.notificationResponse?.payload;
      }
    } catch (_) {}
    return null;
  }

  /// Initialize workmanager - call this in main.dart
  Future<void> initWorkmanager() async {
    if (!_supportsWorkmanager) return;
    await Workmanager().initialize(callbackDispatcher);
  }

  /// Whether the OS currently lets this app post notifications.
  ///
  /// With [interactive] (the default) the system permission prompt is shown
  /// when permission has not been decided yet. Pass `interactive: false` from
  /// startup / resume paths: those must never pop system dialogs or jump the
  /// user into the alarm settings screen.
  Future<bool> requestPermission({bool interactive = true}) async {
    if (!_supportsNotifications) return false;
    if (!_initialized) await init();

    final android = _android;
    if (android != null) {
      var enabled = await android.areNotificationsEnabled() ?? false;
      if (!enabled && interactive) {
        enabled = await android.requestNotificationsPermission() ?? false;
      }
      if (enabled && interactive) {
        await _ensureExactAlarmPermission();
      }
      return enabled;
    }

    final ios = _ios;
    if (ios != null) {
      if (!interactive) {
        final current = await ios.checkPermissions();
        return current?.isEnabled ?? false;
      }
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }

    final macOS = _macOS;
    if (macOS != null) {
      if (!interactive) {
        final current = await macOS.checkPermissions();
        return current?.isEnabled ?? false;
      }
      return await macOS.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return false;
  }

  /// Android 12+ gates exact alarms behind a special-access setting. Only
  /// send the user there when it is actually missing.
  Future<void> _ensureExactAlarmPermission() async {
    final android = _android;
    if (android == null) return;
    try {
      final canExact = await android.canScheduleExactNotifications() ?? true;
      if (!canExact) {
        await android.requestExactAlarmsPermission();
      }
    } catch (e) {
      debugPrint('Could not request exact alarm permission: $e');
    }
  }

  /// Picks the alarm mode the OS will honour. `exact` (without allowWhileIdle)
  /// is deferred during Doze, which is exactly when a reminder matters.
  Future<AndroidScheduleMode> _preferredScheduleMode() async {
    final android = _android;
    if (android == null) return AndroidScheduleMode.exactAllowWhileIdle;
    try {
      final canExact = await android.canScheduleExactNotifications() ?? true;
      return canExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
    } catch (_) {
      return AndroidScheduleMode.inexactAllowWhileIdle;
    }
  }

  /// Single scheduling entry point: tries the preferred mode and falls back
  /// to an inexact alarm if the OS refuses the exact one.
  Future<void> _schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    required NotificationDetails details,
    String? payload,
    DateTimeComponents? repeat,
  }) async {
    final mode = await _preferredScheduleMode();
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        details,
        payload: payload,
        androidScheduleMode: mode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: repeat,
      );
    } catch (e) {
      if (mode == AndroidScheduleMode.inexactAllowWhileIdle) {
        debugPrint('Scheduling notification $id failed: $e');
        return;
      }
      try {
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          when,
          details,
          payload: payload,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: repeat,
        );
      } catch (e2) {
        debugPrint('Scheduling notification $id failed: $e2');
      }
    }
  }

  static const _dailyReminderDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'daily_reminder',
      'Daily Reminder',
      channelDescription: 'Daily goal progress reminder',
      importance: Importance.max,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
  );

  /// Schedule the daily reminder as a repeating zoned notification.
  /// (WorkManager periodic tasks reschedule relative to the previous run,
  /// so Doze delays accumulate and the reminder drifts later every day.)
  Future<void> scheduleDailyReminder({
    required int hour,
    required int minute,
    bool interactive = false,
  }) async {
    if (!_supportsNotifications) return;
    if (!_initialized) await init();

    final granted = await requestPermission(interactive: interactive);
    if (!granted) return;

    // Cancel the legacy workmanager-based reminder and any pending one.
    if (_supportsWorkmanager) {
      await Workmanager().cancelByTag('daily_reminder');
    }
    await _plugin.cancel(_dailyReminderId);

    await _schedule(
      id: _dailyReminderId,
      title: 'RoadmapX Reminder',
      body: 'Time to check on your goals! Keep the streak alive 🔥',
      when: _nextDailyTime(hour, minute),
      details: _dailyReminderDetails,
      payload: _dailyReminderPayload,
      repeat: DateTimeComponents.time,
    );
  }

  tz.TZDateTime _nextDailyTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!scheduled.isAfter(now)) {
      scheduled = tz.TZDateTime(
          tz.local, now.year, now.month, now.day + 1, hour, minute);
    }
    return scheduled;
  }

  /// Show the daily reminder notification (called by workmanager or manually)
  Future<void> _showDailyReminderNotification() async {
    await _plugin.show(
      _dailyReminderId,
      'RoadmapX Reminder',
      'Time to check on your goals! Keep the streak alive 🔥',
      _dailyReminderDetails,
      payload: _dailyReminderPayload,
    );
  }

  Future<void> cancelDailyReminder() async {
    if (!_supportsNotifications) return;
    if (_supportsWorkmanager) {
      await Workmanager().cancelByTag('daily_reminder');
    }
    await _plugin.cancel(_dailyReminderId);
  }

  // Habit reminders occupy ids 10000..50007. Each habit owns a block of 8:
  // slot 0 for an every-day reminder, slots 1..7 for one weekday each
  // (DateTime.monday..DateTime.sunday).
  int _habitNotificationBase(String habitUid) =>
      10000 + (habitUid.hashCode.abs() % 5000) * 8;

  // Id used by builds before per-weekday reminders existed; cancelled so an
  // upgrade does not leave a duplicate daily alarm behind.
  int _legacyHabitNotificationId(String habitUid) =>
      10000 + (habitUid.hashCode.abs() % 40000);

  static const _habitDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'habit_reminders',
      'Habit Reminders',
      channelDescription: 'Reminders for daily habits',
      importance: Importance.max,
      priority: Priority.high,
      channelShowBadge: true,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.reminder,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
    macOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  /// [repeatDays] uses DateTime's convention (1 = Monday … 7 = Sunday).
  /// Null or all seven days means a daily reminder.
  Future<void> scheduleHabitReminder({
    required String habitUid,
    required String habitLabel,
    required int hour,
    required int minute,
    List<int>? repeatDays,
    bool interactive = true,
  }) async {
    if (!_supportsNotifications) return;
    if (!_initialized) await init();
    final granted = await requestPermission(interactive: interactive);
    if (!granted) return;

    await cancelHabitReminder(habitUid);

    final base = _habitNotificationBase(habitUid);
    final title = 'Habit Reminder';
    final body = 'Time for "$habitLabel"! Keep your streak going 🔥';
    final payload = '$_habitPayloadPrefix$habitUid';

    final days = (repeatDays ?? const [])
        .where((d) => d >= DateTime.monday && d <= DateTime.sunday)
        .toSet();
    if (days.isEmpty || days.length == 7) {
      await _schedule(
        id: base,
        title: title,
        body: body,
        when: _nextDailyTime(hour, minute),
        details: _habitDetails,
        payload: payload,
        repeat: DateTimeComponents.time,
      );
      return;
    }

    final now = tz.TZDateTime.now(tz.local);
    for (final weekday in days) {
      await _schedule(
        id: base + weekday,
        title: title,
        body: body,
        // _nextWeekdayTime expects Sunday = 0.
        when: _nextWeekdayTime(weekday % 7, hour, minute, from: now),
        details: _habitDetails,
        payload: payload,
        repeat: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  Future<void> cancelHabitReminder(String habitUid) async {
    if (!_supportsNotifications) return;
    if (!_initialized) await init();
    final base = _habitNotificationBase(habitUid);
    for (var slot = 0; slot <= 7; slot++) {
      await _plugin.cancel(base + slot);
    }
    await _plugin.cancel(_legacyHabitNotificationId(habitUid));
  }

  /// Re-registers every weekly schedule notification from the current items.
  ///
  /// Called from startup and resume, so it never prompts for permission; the
  /// prompt belongs to the user action that enabled notifications.
  Future<void> syncScheduleNotifications(
    List<ScheduleItem> items, {
    bool interactive = false,
  }) async {
    if (!_supportsNotifications) return;
    if (!_initialized) await init();

    await _cancelScheduleNotifications();

    final granted = await requestPermission(interactive: interactive);
    if (!granted) return;

    final now = tz.TZDateTime.now(tz.local);
    for (final item in items) {
      if (!item.isActive || item.weekdays.isEmpty) continue;

      final parsed = _parseTime(item.time);
      if (parsed == null) continue;

      for (final weekday in item.weekdays.toSet()) {
        if (weekday < 0 || weekday > 6) continue;
        final next = _nextWeekdayTime(weekday, parsed.$1, parsed.$2, from: now);

        // Bases spaced far enough apart that id ranges can't collide
        // (cancellation is payload-based, so re-basing is safe).
        final eventId = 100000000 + (item.id * 10) + weekday;
        final priorId = 200000000 + (item.id * 10) + weekday;
        await _scheduleViaZonedSchedule(eventId, priorId, item, next);
      }
    }
  }

  static const _taskDueDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'task_due',
      'Task Due',
      channelDescription: 'Task due date reminders',
      importance: Importance.max,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
  );

  /// [reminderHour]/[reminderMinute] are used for due dates that carry no
  /// time of day (the date picker stores midnight): "Due now" at 00:00 is
  /// useless and a task due today would never be scheduled at all.
  Future<void> syncTaskDueNotifications(
    List<Task> tasks, {
    bool enabled = true,
    bool interactive = false,
    int reminderHour = 9,
    int reminderMinute = 0,
  }) async {
    if (!_supportsNotifications) return;
    if (!_initialized) await init();
    await _cancelTaskDueNotifications();
    if (!enabled) return;

    final granted = await requestPermission(interactive: interactive);
    if (!granted) return;

    final now = DateTime.now();
    for (final task in tasks) {
      if (task.isCompleted || task.dueDate == null) continue;
      final due = task.dueDate!;
      final hasTime = due.hour != 0 || due.minute != 0;
      final fireAt = hasTime
          ? due
          : DateTime(
              due.year, due.month, due.day, reminderHour, reminderMinute);
      if (!fireAt.isAfter(now)) continue;

      await _schedule(
        id: 300000000 + task.id,
        title: 'Task due: ${task.text}',
        body: hasTime ? 'Due now' : 'Due today',
        when: tz.TZDateTime.from(fireAt, tz.local),
        details: _taskDueDetails,
        payload: '$_taskDuePayloadPrefix${task.id}',
      );
    }
  }

  static const _scheduleEventDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'schedule_events',
      'Schedule Events',
      channelDescription: 'Notifications for scheduled routines/events',
      importance: Importance.max,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
  );

  static const _schedulePriorDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'schedule_prior',
      'Upcoming Event Alerts',
      channelDescription: '5-minute alerts before scheduled events',
      importance: Importance.max,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
  );

  Future<void> _scheduleViaZonedSchedule(
    int eventId,
    int priorId,
    ScheduleItem item,
    tz.TZDateTime next,
  ) async {
    await _schedule(
      id: eventId,
      title: item.label,
      body: item.detail.isEmpty ? 'Scheduled event for now.' : item.detail,
      when: next,
      details: _scheduleEventDetails,
      payload: '$_schedulePayloadPrefix${item.id}:event',
      repeat: DateTimeComponents.dayOfWeekAndTime,
    );

    final prior = next.subtract(const Duration(minutes: 5));
    if (!prior.isAfter(tz.TZDateTime.now(tz.local))) return;

    await _schedule(
      id: priorId,
      title: 'Upcoming: ${item.label}',
      body: 'Starts in 5 minutes',
      when: prior,
      details: _schedulePriorDetails,
      payload: '$_schedulePayloadPrefix${item.id}:prior',
      repeat: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  /// Show event notification (called by workmanager or manually)
  Future<void> _showEventNotification(String label, String detail) async {
    final id = label.hashCode.abs() % 100000;
    await _plugin.show(id, label, detail, _scheduleEventDetails);
  }

  /// Show prior notification (called by workmanager or manually)
  Future<void> _showPriorNotification(String label) async {
    final id = (label.hashCode.abs() + 1) % 100000;
    await _plugin.show(
        id, 'Upcoming: $label', 'Starts in 5 minutes', _schedulePriorDetails);
  }

  Future<void> _cancelScheduleNotifications() async {
    if (_supportsWorkmanager) {
      await Workmanager().cancelByTag('schedule_events');
    }
    final pending = await _plugin.pendingNotificationRequests();
    for (final req in pending) {
      if (req.payload?.startsWith(_schedulePayloadPrefix) ?? false) {
        await _plugin.cancel(req.id);
      }
    }
  }

  Future<void> _cancelTaskDueNotifications() async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final req in pending) {
      if (req.payload?.startsWith(_taskDuePayloadPrefix) ?? false) {
        await _plugin.cancel(req.id);
      }
    }
  }

  (int, int)? _parseTime(String time) {
    try {
      final trimmed = time.trim();
      if (trimmed.isEmpty) return null;

      // Dots between digits are time separators ("6.30 PM"); other dots
      // are abbreviation periods ("P.M.") and can be dropped.
      final normalized = trimmed
          .replaceAllMapped(
              RegExp(r'(\d)\.(\d)'), (m) => '${m.group(1)}:${m.group(2)}')
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

      // "9 AM" / "12PM" without minutes.
      final hourOnly = RegExp(r'^(\d{1,2})\s*([AP]M)$').firstMatch(normalized);
      if (hourOnly != null) {
        var h = int.parse(hourOnly.group(1)!);
        final p = hourOnly.group(2)!;
        if (h < 1 || h > 12) return null;
        if (p == 'PM' && h != 12) h += 12;
        if (p == 'AM' && h == 12) h = 0;
        return (h, 0);
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

    // Add days as date components, not absolute time: `.add(Duration(...))`
    // across a DST change shifts the wall-clock hour, and the weekly repeat
    // then fires at the wrong hour until the next re-sync.
    var candidate = tz.TZDateTime(
      tz.local,
      from.year,
      from.month,
      from.day + diffDays,
      hour,
      minute,
    );

    if (!candidate.isAfter(from)) {
      candidate = tz.TZDateTime(
        tz.local,
        candidate.year,
        candidate.month,
        candidate.day + 7,
        hour,
        minute,
      );
    }

    return candidate;
  }

  static const _testDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'test_channel',
      'Test Notifications',
      channelDescription: 'For testing notification delivery',
      importance: Importance.max,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
    ),
    macOS: DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
    ),
  );

  /// Immediate notification for testing. Returns false when the OS has
  /// notifications disabled for the app.
  Future<bool> showTestNotification() async {
    if (!_supportsNotifications) return false;
    if (!_initialized) await init();

    final granted = await requestPermission();
    if (!granted) return false;

    await _plugin.show(
      _testNotificationId,
      'RoadmapX Test',
      'If you see this, notifications are working! 🎉',
      _testDetails,
    );
    return true;
  }

  /// Scheduled test notification. Uses the same alarm path as the real
  /// reminders so it proves that scheduled delivery works, not just show().
  Future<bool> showTestScheduledNotification({
    Duration delay = const Duration(seconds: 10),
  }) async {
    if (!_supportsNotifications) return false;
    if (!_initialized) await init();

    final granted = await requestPermission();
    if (!granted) return false;

    await _plugin.cancel(_testScheduledNotificationId);
    await _schedule(
      id: _testScheduledNotificationId,
      title: 'RoadmapX Scheduled Test',
      body: 'This notification was scheduled ${delay.inSeconds} seconds ago.',
      when: tz.TZDateTime.now(tz.local).add(delay),
      details: _testDetails,
    );
    return true;
  }

  /// Diagnostic snapshot for the settings screen.
  Future<NotificationStatus> status() async {
    if (!_supportsNotifications) {
      return const NotificationStatus(
        supported: false,
        enabled: false,
        exactAlarms: false,
        pendingCount: 0,
      );
    }
    if (!_initialized) await init();
    final enabled = await requestPermission(interactive: false);
    var exact = true;
    final android = _android;
    if (android != null) {
      exact = await android.canScheduleExactNotifications() ?? true;
    }
    final pending = await _plugin.pendingNotificationRequests();
    return NotificationStatus(
      supported: true,
      enabled: enabled,
      exactAlarms: exact,
      pendingCount: pending.length,
    );
  }

  /// Opens the Android exact-alarm settings page when the permission is
  /// missing; a no-op elsewhere.
  Future<void> openExactAlarmSettings() => _ensureExactAlarmPermission();

  static const _ritualDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'daily_reminder',
      'Daily Reminder',
      channelDescription: 'Daily goal progress reminder',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
  );

  /// The morning "plan your day" and evening "wrap up" reminders, each
  /// daily at the given time, or off when null. Never prompts.
  Future<void> scheduleRituals({
    ({int hour, int minute})? morning,
    ({int hour, int minute})? evening,
  }) async {
    if (!_supportsNotifications) return;
    if (!_initialized) await init();
    await _plugin.cancel(_morningPlanId);
    await _plugin.cancel(_eveningWrapId);
    if (!await requestPermission(interactive: false)) return;
    if (morning != null) {
      await _schedule(
        id: _morningPlanId,
        title: 'Plan your day ☀️',
        body: 'Pick your top 3 for today. Takes 2 minutes.',
        when: _nextDailyTime(morning.hour, morning.minute),
        details: _ritualDetails,
        payload: _planPayload,
        repeat: DateTimeComponents.time,
      );
    }
    if (evening != null) {
      await _schedule(
        id: _eveningWrapId,
        title: 'Wrap up your day 🌙',
        body: 'Move what is left to tomorrow and note how today went.',
        when: _nextDailyTime(evening.hour, evening.minute),
        details: _ritualDetails,
        payload: _wrapPayload,
        repeat: DateTimeComponents.time,
      );
    }
  }

  /// Tells the user a focus session is over, even if they left the app.
  Future<void> scheduleFocusEnd(DateTime at, {String? taskText}) async {
    if (!_supportsNotifications) return;
    if (!_initialized) await init();
    await _plugin.cancel(_focusEndId);
    if (!await requestPermission(interactive: false)) return;
    await _schedule(
      id: _focusEndId,
      title: 'Focus session complete 🎉',
      body: taskText == null
          ? 'Nice work. Take a short break.'
          : 'Nice work on "$taskText". Take a short break.',
      when: tz.TZDateTime.from(at, tz.local),
      details: _testDetails,
      payload: _focusPayload,
    );
  }

  Future<void> cancelFocusEnd() async {
    if (!_supportsNotifications) return;
    if (!_initialized) await init();
    await _plugin.cancel(_focusEndId);
  }

  Future<void> cancelCompanionNudge() async {
    if (!_supportsNotifications) return;
    if (!_initialized) await init();
    await _plugin.cancel(_companionNudgeId);
  }

  /// One reminder, at the moment the pet is due to run low on something.
  /// Re-planned on every change and launch, so feeding the pet moves it.
  Future<void> scheduleCompanionNudge({
    required DateTime at,
    required String name,
    required String complaint,
  }) async {
    if (!_supportsNotifications) return;
    if (!_initialized) await init();
    await _plugin.cancel(_companionNudgeId);
    if (!await requestPermission(interactive: false)) return;

    await _schedule(
      id: _companionNudgeId,
      title: '$name is getting $complaint',
      body: 'Finish a task to earn coins, then look after $name in the Pet tab.',
      when: tz.TZDateTime.from(at, tz.local),
      details: const NotificationDetails(
        android: AndroidNotificationDetails(
          'companion',
          'Companion',
          channelDescription: 'Reminders when your pet needs looking after',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      ),
      payload: _companionPayload,
    );
  }

  /// Maps a tapped notification payload to the route that should open.
  static String? routeForPayload(String payload) {
    if (payload.startsWith(_habitPayloadPrefix)) return '/habits';
    if (payload.startsWith(_schedulePayloadPrefix)) return '/schedule';
    if (payload.startsWith(_taskDuePayloadPrefix)) return '/today';
    if (payload == _dailyReminderPayload) return '/today';
    if (payload == _companionPayload) return '/pet';
    if (payload == _planPayload) return '/today?ritual=plan';
    if (payload == _focusPayload) return '/focus-timer';
    if (payload == _wrapPayload) return '/today?ritual=wrap';
    return null;
  }

  Future<void> cancelAll() async {
    if (!_supportsNotifications) return;
    if (!_initialized) await init();
    await _plugin.cancelAll();
  }
}

class NotificationStatus {
  final bool supported;
  final bool enabled;
  final bool exactAlarms;
  final int pendingCount;

  const NotificationStatus({
    required this.supported,
    required this.enabled,
    required this.exactAlarms,
    required this.pendingCount,
  });
}
