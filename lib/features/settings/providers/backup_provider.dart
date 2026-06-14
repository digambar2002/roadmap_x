import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/services/backup_service.dart';
import '../../../core/services/data_export_service.dart';

class BackupState {
  const BackupState({
    this.lastBackupPath,
    this.lastBackupAt,
    this.isBusy = false,
  });

  final String? lastBackupPath;
  final String? lastBackupAt;
  final bool isBusy;

  BackupState copyWith({
    String? lastBackupPath,
    String? lastBackupAt,
    bool? isBusy,
  }) {
    return BackupState(
      lastBackupPath: lastBackupPath ?? this.lastBackupPath,
      lastBackupAt: lastBackupAt ?? this.lastBackupAt,
      isBusy: isBusy ?? this.isBusy,
    );
  }
}

class BackupNotifier extends AutoDisposeAsyncNotifier<BackupState> {
  @override
  Future<BackupState> build() async {
    return BackupState(
      lastBackupPath: await BackupService.instance.latestBackupPath(),
      lastBackupAt: await BackupService.instance.latestBackupAt(),
    );
  }

  Future<String?> createBackupNow() async {
    state = AsyncData(state.valueOrNull?.copyWith(isBusy: true) ??
        const BackupState(isBusy: true));
    final path = await BackupService.instance.createBackup();
    state = AsyncData(
      BackupState(
        lastBackupPath: await BackupService.instance.latestBackupPath(),
        lastBackupAt: await BackupService.instance.latestBackupAt(),
        isBusy: false,
      ),
    );
    return path;
  }

  Future<ImportCounts?> restoreLatest({
    ImportMode mode = ImportMode.merge,
  }) async {
    state = AsyncData(state.valueOrNull?.copyWith(isBusy: true) ??
        const BackupState(isBusy: true));
    final counts = await BackupService.instance.restoreLatest(mode: mode);
    state = AsyncData(
      BackupState(
        lastBackupPath: await BackupService.instance.latestBackupPath(),
        lastBackupAt: await BackupService.instance.latestBackupAt(),
        isBusy: false,
      ),
    );
    return counts;
  }
}

final backupProvider =
    AutoDisposeAsyncNotifierProvider<BackupNotifier, BackupState>(
  BackupNotifier.new,
);
