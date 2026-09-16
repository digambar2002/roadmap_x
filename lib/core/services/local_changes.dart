import '../sync/sync_service.dart';
import 'backup_service.dart';
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

  Future<void> notify() async {
    await BackupService.instance.scheduleBackup();
    SyncService.instance.schedulePush();
    await WidgetSyncService.instance.syncTodayTasks();
  }

  /// Runs [action] without triggering backup, push, or widget sync. Used while
  /// importing or restoring, where the writes are not user edits.
  Future<T> suspended<T>(Future<T> Function() action) =>
      BackupService.instance.withoutScheduling(action);
}
