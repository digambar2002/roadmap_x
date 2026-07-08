import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'data_export_service.dart';

class BackupService {
  BackupService._();
  static final instance = BackupService._();

  static const _latestBackupPathKey = 'latest_backup_path';
  static const _latestBackupAtKey = 'latest_backup_at';
  static const _restoreMarkerKey = 'latest_restore_marker';
  static const _backupTaskName = 'auto_backup';
  static const _autoBackupTaskId = 'roadmapx_auto_backup';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  Timer? _debounceTimer;
  var _suspendScheduling = false;

  Future<void> init() async {
    await _registerAutoBackupTask();
  }

  Future<void> _registerAutoBackupTask() async {
    try {
      await Workmanager().registerPeriodicTask(
        _autoBackupTaskId,
        _backupTaskName,
        frequency: const Duration(hours: 12),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
    } catch (_) {
      // Workmanager may throw if not available on the current platform.
    }
  }

  Future<T> withoutScheduling<T>(Future<T> Function() action) async {
    final previous = _suspendScheduling;
    _suspendScheduling = true;
    try {
      return await action();
    } finally {
      _suspendScheduling = previous;
    }
  }

  Future<void> scheduleBackup() async {
    if (_suspendScheduling) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 3), () async {
      await createBackup();
    });
  }

  Future<String?> createBackup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final exportJson = await DataExportService.instance.exportToJson(
        preferences: _exportablePreferences(prefs),
      );

      final filename = _buildFileName();
      final filePath = await _writeBackupFile(filename, exportJson);
      if (filePath == null) return null;

      await _secureStorage.write(key: _latestBackupPathKey, value: filePath);
      await _secureStorage.write(
        key: _latestBackupAtKey,
        value: DateTime.now().toIso8601String(),
      );
      return filePath;
    } catch (_) {
      return null;
    }
  }

  Future<String?> performAutoBackup() => createBackup();

  Future<ImportCounts?> restoreLatest({
    ImportMode mode = ImportMode.merge,
  }) async {
    try {
      final backup = await _readLatestBackup();
      if (backup == null) return null;

      final imported = await withoutScheduling(
        () => DataExportService.instance.importFromJson(backup, mode: mode),
      );

      final prefs = await SharedPreferences.getInstance();
      await _restorePreferences(prefs, imported.preferences);
      await _secureStorage.write(
        key: _restoreMarkerKey,
        value: DateTime.now().toIso8601String(),
      );
      return imported.counts;
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasPendingRestoreMarker() async {
    final marker = await _secureStorage.read(key: _restoreMarkerKey);
    return marker != null;
  }

  Future<void> clearRestoreMarker() =>
      _secureStorage.delete(key: _restoreMarkerKey);

  Future<void> restorePreferences(Map<String, dynamic> preferences) async {
    final prefs = await SharedPreferences.getInstance();
    await _restorePreferences(prefs, preferences);
  }

  Future<String?> latestBackupPath() =>
      _secureStorage.read(key: _latestBackupPathKey);

  Future<String?> latestBackupAt() =>
      _secureStorage.read(key: _latestBackupAtKey);

  Future<String?> _readLatestBackup() async {
    final storedPath = await _secureStorage.read(key: _latestBackupPathKey);
    if (storedPath != null) {
      final file = File(storedPath);
      if (await file.exists()) {
        return file.readAsString();
      }
    }

    final dir = await _defaultBackupDirectory();
    if (dir == null || !await dir.exists()) return null;
    final entries = dir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    if (entries.isEmpty) return null;

    final latest = entries.first;
    await _secureStorage.write(key: _latestBackupPathKey, value: latest.path);
    return latest.readAsString();
  }

  Future<String?> _writeBackupFile(String filename, String contents) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final downloads = Directory('/storage/emulated/0/Download');
      if (await downloads.exists()) {
        final file = File('${downloads.path}/$filename');
        await file.writeAsString(contents);
        return file.path;
      }
    }

    final dir = await _defaultBackupDirectory();
    if (dir == null) return null;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}/$filename');
    await file.writeAsString(contents);

    return file.path;
  }

  Future<Directory?> _defaultBackupDirectory() async {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return downloads;
    return getApplicationDocumentsDirectory();
  }

  String _buildFileName() {
    return 'roadmapx_backup.json';
  }

  Map<String, dynamic> _exportablePreferences(SharedPreferences prefs) {
    final data = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      data[key] = prefs.get(key);
    }
    return data;
  }

  Future<void> _restorePreferences(
    SharedPreferences prefs,
    Map<String, dynamic> restored,
  ) async {
    for (final entry in restored.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is String) {
        await prefs.setString(key, value);
      } else if (value is List) {
        await prefs.setStringList(
          key,
          value.map((item) => item.toString()).toList(),
        );
      }
    }
  }
}
