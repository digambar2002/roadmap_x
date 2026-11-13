import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/utils/prefs_utils.dart';
import 'core/db/db_migration.dart';
import 'core/db/isar_service.dart';
import 'core/gamification/gamification_service.dart';
import 'core/router/app_router.dart';
import 'core/services/backup_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/local_changes.dart';
import 'core/services/onboarding.dart';
import 'core/services/shared_preferences_provider.dart';
import 'core/services/synced_settings.dart';
import 'core/services/widget_sync_service.dart';
import 'core/sync/account_service.dart';
import 'core/sync/sync_service.dart';
import 'core/theme/app_theme.dart';
import 'features/analytics/providers/activity_provider.dart';
import 'features/schedule/data/schedule_repository.dart';
import 'features/schedule/providers/schedule_provider.dart';
import 'features/habits/providers/habit_provider.dart';
import 'features/tasks/data/task_repository.dart';
import 'features/settings/providers/settings_provider.dart';
import 'shared/widgets/restore_backup_gate.dart';
import 'core/services/sound_service.dart';
import 'package:flutter/services.dart';
import 'features/tasks/presentation/quick_add_task_sheet.dart';
import 'features/ritual/data/ritual_settings.dart';
import 'features/focus/data/focus_sessions.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await IsarService.instance.init();
  // Notifications are a nice-to-have; a platform that cannot provide them
  // must not stop the app from starting. This is awaited before runApp, so an
  // uncaught throw here means no window ever appears.
  try {
    await NotificationService.instance.init();
    await NotificationService.instance.initWorkmanager();
  } catch (error, stack) {
    debugPrint('Notification setup failed, continuing without it: $error');
    debugPrintStack(stackTrace: stack);
  }
  await BackupService.instance.init();

  final prefs = await SharedPreferences.getInstance();

  // Must run before anything reads goals, tasks or day history: it stamps the
  // sync metadata onto rows written by pre-sync builds and lifts the habit and
  // schedule history out of SharedPreferences into real rows.
  await DbMigration.instance.run(prefs);
  await SyncedSettings.instance.captureExisting(prefs);
  // Upgrading users already have data; the welcome question is only for a
  // genuinely empty first run.
  await Onboarding.skipForExistingUsers(prefs);

  // Both are no-ops without SUPABASE_* dart-defines, and for accounts that
  // have not been activated. The app is fully usable either way.
  await AccountService.instance.init(prefs);
  await SyncService.instance.init(prefs);
  final dailyReminderEnabled =
      PrefsUtils.readBool(prefs, 'daily_reminder_enabled');
  final dailyReminderHour = prefs.getInt('daily_reminder_hour') ?? 9;
  final dailyReminderMinute = prefs.getInt('daily_reminder_minute') ?? 0;
  final taskDueNotificationsEnabled = PrefsUtils.readBool(
      prefs, 'task_due_notifications_enabled',
      fallback: true);
  if (dailyReminderEnabled) {
    await NotificationService.instance.scheduleDailyReminder(
      hour: dailyReminderHour,
      minute: dailyReminderMinute,
    );
  }

  final scheduleItems = await ScheduleRepository.instance.getAll();
  final allTasks = await TaskRepository.instance.getAll();
  await NotificationService.instance.syncScheduleNotifications(scheduleItems);
  await NotificationService.instance.syncTaskDueNotifications(
    allTasks,
    enabled: taskDueNotificationsEnabled,
    reminderHour: dailyReminderHour,
    reminderMinute: dailyReminderMinute,
  );

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const RoadmapXApp(),
    ),
  );
}

class RoadmapXApp extends ConsumerStatefulWidget {
  const RoadmapXApp({super.key});

  @override
  ConsumerState<RoadmapXApp> createState() => _RoadmapXAppState();
}

class _RoadmapXAppState extends ConsumerState<RoadmapXApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future<void>.microtask(_bootstrapRuntimeServices);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationTapSub?.cancel();
    super.dispose();
  }

  DateTime _lastActiveDay = DateTime.now();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _rolloverDayIfNeeded();
      Future<void>.microtask(() async {
        await _syncNotifications();
        await LocalChanges.instance.notify();
        await _checkSharedText();
        await _settleFocus();
      });
    }
  }

  /// Providers that capture "today" at build time go stale when the app
  /// sits in the background past midnight; reset them on the first resume
  /// of a new day.
  void _rolloverDayIfNeeded() {
    final now = DateTime.now();
    final sameDay = now.year == _lastActiveDay.year &&
        now.month == _lastActiveDay.month &&
        now.day == _lastActiveDay.day;
    _lastActiveDay = now;
    if (sameDay) return;

    ref.invalidate(selectedScheduleDateProvider);
    ref.invalidate(todayHabitChecksProvider);
    ref.read(habitActivityTickProvider.notifier).state++;
    ref.read(activityTickProvider.notifier).state++;
  }

  StreamSubscription<String>? _notificationTapSub;

  Future<void> _bootstrapRuntimeServices() async {
    // After the first frame, so preloading sounds never delays the launch.
    unawaited(SoundService.instance.init(ref.read(sharedPreferencesProvider)));
    await BackupService.instance.init();
    await _syncNotifications();
    await WidgetSyncService.instance.syncTodayTasks();
    await WidgetSyncService.instance.initLaunchListener((uri) {
      if (uri.host == 'today' || uri.path.contains('today')) {
        ref.read(appRouterProvider).go('/today');
      }
    });

    // Route notification taps: the one that launched the app (cold start)
    // and any tapped while it is running.
    final launchPayload =
        await NotificationService.instance.consumeLaunchPayload();
    if (launchPayload != null) _openRouteForPayload(launchPayload);
    _notificationTapSub = NotificationService.instance.onNotificationTapped
        .listen(_openRouteForPayload);
    await _checkSharedText();
    await _settleFocus();
  }

  /// A focus session that ended while the app was closed still counts.
  Future<void> _settleFocus() async {
    final credited = await FocusSessions.instance.settleRunning();
    if (credited != null && mounted) bumpActivityTick(ref);
  }

  static const _shareChannel = MethodChannel('roadmapx/share');

  /// Text shared into the app from elsewhere ("Share → RoadmapX").
  Future<void> _checkSharedText() async {
    String? text;
    try {
      text = await _shareChannel.invokeMethod<String>('takeSharedText');
    } catch (_) {
      return; // Not Android, or no channel in this build.
    }
    if (text == null || text.trim().isEmpty || !mounted) return;
    final router = ref.read(appRouterProvider);
    router.go('/today');
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final ctx = router.routerDelegate.navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await showQuickAddTask(ctx, initialText: text.trim());
  }

  void _openRouteForPayload(String payload) {
    final route = NotificationService.routeForPayload(payload);
    if (route == null || !mounted) return;
    ref.read(appRouterProvider).go(route);
  }

  Future<void> _syncNotifications() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final taskDueEnabled = PrefsUtils.readBool(
      prefs,
      'task_due_notifications_enabled',
      fallback: true,
    );
    final allScheduleItems = await ScheduleRepository.instance.getAll();
    final allTasks = await TaskRepository.instance.getAll();
    await NotificationService.instance
        .syncScheduleNotifications(allScheduleItems);
    await NotificationService.instance.syncTaskDueNotifications(
      allTasks,
      enabled: taskDueEnabled,
      reminderHour: prefs.getInt('daily_reminder_hour') ?? 9,
      reminderMinute: prefs.getInt('daily_reminder_minute') ?? 0,
    );
    await RitualSettings.sync(prefs);
    await GamificationService.instance.syncNudge();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final settingsAsync = ref.watch(settingsProvider);
    final themeMode = settingsAsync.when(
      data: (state) {
        switch (state.themeMode) {
          case 'light':
            return ThemeMode.light;
          case 'system':
            return ThemeMode.system;
          default:
            return ThemeMode.dark;
        }
      },
      loading: () => ThemeMode.dark,
      error: (_, __) => ThemeMode.dark,
    );

    final darkStyle =
        DarkModeStyle.fromKey(settingsAsync.valueOrNull?.darkModeStyle);
    final darkTheme = AppTheme.buildDark(darkStyle);

    return MaterialApp.router(
      title: 'RoadmapX',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) => Theme(
        // Inside MaterialApp the theme is localized, so its text styles have
        // real sizes and the desktop scale can be applied to them.
        data: AppTheme.densifyForPointer(Theme.of(context)),
        child: RestoreBackupGate(
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
