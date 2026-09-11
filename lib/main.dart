import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/utils/prefs_utils.dart';
import 'core/db/db_migration.dart';
import 'core/db/isar_service.dart';
import 'core/router/app_router.dart';
import 'core/services/backup_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/local_changes.dart';
import 'core/services/shared_preferences_provider.dart';
import 'core/services/synced_settings.dart';
import 'core/sync/account_service.dart';
import 'core/sync/sync_service.dart';
import 'core/theme/app_theme.dart';
import 'features/analytics/providers/activity_provider.dart';
import 'features/schedule/data/schedule_repository.dart';
import 'features/schedule/providers/schedule_provider.dart';
import 'features/settings/providers/habit_checkin_provider.dart';
import 'features/tasks/data/task_repository.dart';
import 'features/settings/providers/settings_provider.dart';
import 'shared/widgets/restore_backup_gate.dart';

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

  // Both are no-ops without SUPABASE_* dart-defines, and for accounts that
  // have not been activated. The app is fully usable either way.
  await AccountService.instance.init(prefs);
  await SyncService.instance.init(prefs);
  final dailyReminderEnabled =
      PrefsUtils.readBool(prefs, 'daily_reminder_enabled');
  final dailyReminderHour = prefs.getInt('daily_reminder_hour') ?? 9;
  final dailyReminderMinute = prefs.getInt('daily_reminder_minute') ?? 0;
  final taskDueNotificationsEnabled =
      PrefsUtils.readBool(prefs, 'task_due_notifications_enabled', fallback: true);
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

  Future<void> _bootstrapRuntimeServices() async {
    await BackupService.instance.init();
    await _syncNotifications();
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
    );
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

    return MaterialApp.router(
        title: 'RoadmapX',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        routerConfig: router,
        builder: (context, child) => RestoreBackupGate(
          child: child ?? const SizedBox.shrink(),
        ),
      );
  }
}
