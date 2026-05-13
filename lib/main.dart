import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/db/isar_service.dart';
import 'core/router/app_router.dart';
import 'core/services/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'features/schedule/data/schedule_repository.dart';
import 'features/settings/providers/settings_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await IsarService.instance.init();
  await NotificationService.instance.init();
  await NotificationService.instance.initWorkmanager();

  final prefs = await SharedPreferences.getInstance();
  final dailyReminderEnabled = prefs.getBool('daily_reminder_enabled') ?? false;
  if (dailyReminderEnabled) {
    await NotificationService.instance.scheduleDailyReminder(
      hour: 9,
      minute: 0,
    );
  }

  final allScheduleItems = await ScheduleRepository.instance.getAll();
  await NotificationService.instance
      .syncScheduleNotifications(allScheduleItems);
  runApp(const ProviderScope(child: RoadmapXApp()));
}

class RoadmapXApp extends ConsumerWidget {
  const RoadmapXApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final settingsAsync = ref.watch(settingsProvider);
    final themeMode = settingsAsync.when(
      data: (s) {
        switch (s.themeMode) {
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
    );
  }
}
