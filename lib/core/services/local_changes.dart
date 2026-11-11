import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/tasks/data/task_repository.dart';
import '../sync/sync_service.dart';
import '../utils/prefs_utils.dart';
import 'backup_service.dart';
import 'notification_service.dart';
import 'widget_sync_service.dart';

/// Single fan-out point for "the user just changed something".
///
/// Repositories previously called [BackupService.scheduleBackup] directly from
/// ~30 sites. Sync needs the same signal, and threading a second call through
/// every one of them invites the bug where a new mutation remembers one and
/// forgets the other. One call, three subscribers.
class LocalChanges {
  LocalChanges._();
  static final LocalChanges instance = LocalChanges._();

  Timer? _dueTimer;

  Future<void> notify() async {
    await BackupService.instance.scheduleBackup();
    SyncService.instance.schedulePush();
    await WidgetSyncService.instance.syncTodayTasks();
    _scheduleTaskDueResync();
  }

  /// Task due alerts used to be rebuilt only on launch/resume, so a deleted
  /// or completed task kept its alarm and a new due date got none until then.
  void _scheduleTaskDueResync() {
    _dueTimer?.cancel();
    _dueTimer = Timer(const Duration(seconds: 2), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final enabled = PrefsUtils.readBool(
          prefs,
          'task_due_notifications_enabled',
          fallback: true,
        );
        final tasks = await TaskRepository.instance.getAll();
        await NotificationService.instance.syncTaskDueNotifications(
          tasks,
          enabled: enabled,
          reminderHour: prefs.getInt('daily_reminder_hour') ?? 9,
          reminderMinute: prefs.getInt('daily_reminder_minute') ?? 0,
        );
      } catch (_) {
        // Notifications are best-effort; the next launch re-syncs anyway.
      }
    });
  }

  /// Runs [action] without triggering backup, push, or widget sync. Used while
  /// importing or restoring, where the writes are not user edits.
  Future<T> suspended<T>(Future<T> Function() action) =>
      BackupService.instance.withoutScheduling(action);
}
