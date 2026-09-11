import '../sync/sync_service.dart';
import 'backup_service.dart';

/// Single fan-out point for "the user just changed something".
///
/// Repositories previously called [BackupService.scheduleBackup] directly from
/// ~30 sites. Sync needs the same signal, and threading a second call through
/// every one of them invites the bug where a new mutation remembers one and
/// forgets the other. One call, two subscribers.
class LocalChanges {
  LocalChanges._();
  static final LocalChanges instance = LocalChanges._();

  Future<void> notify() async {
    await BackupService.instance.scheduleBackup();
    SyncService.instance.schedulePush();
  }

  /// Runs [action] without triggering either a backup or a push. Used while
  /// importing or restoring, where the writes are not user edits.
  Future<T> suspended<T>(Future<T> Function() action) =>
      BackupService.instance.withoutScheduling(action);
}
