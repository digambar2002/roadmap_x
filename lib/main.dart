import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/utils/prefs_utils.dart';
import 'core/db/isar_service.dart';
import 'core/router/app_router.dart';
import 'core/services/backup_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/shared_preferences_provider.dart';
import 'core/theme/app_theme.dart';
import 'features/schedule/data/schedule_repository.dart';
import 'features/tasks/data/task_repository.dart';
import 'features/settings/providers/settings_provider.dart';
import 'shared/widgets/restore_backup_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await IsarService.instance.init();
  await NotificationService.instance.init();
  await NotificationService.instance.initWorkmanager();
  await BackupService.instance.init();

  final prefs = await SharedPreferences.getInstance();
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Future<void>.microtask(() async {
        await _syncNotifications();
        await BackupService.instance.scheduleBackup();
      });
    }
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
