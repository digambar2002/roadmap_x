import 'dart:async';
import 'dart:convert';

import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/isar_service.dart';
import '../models/models.dart';

/// Keeps the handful of content-bearing preferences mirrored into Isar so they
/// travel with the rest of the data.
///
/// SharedPreferences stays the read path — it is synchronous and every screen
/// already uses it. This class mirrors writes into [AppSetting] rows on the way
/// out, and writes merged rows back into SharedPreferences on the way in.
class SyncedSettings {
  SyncedSettings._();
  static final SyncedSettings instance = SyncedSettings._();

  /// Deliberately narrow.
  ///
  /// Excluded: `theme_mode` and the notification settings, which describe the
  /// device rather than the user, and would be actively annoying to have
  /// overwritten from a phone onto a laptop. The Gemini API key is a secret
  /// and never leaves the device at all.
  static const Set<String> syncedKeys = {
    'user_name',
    'non_neg_0_label',
    'non_neg_1_label',
    'non_neg_2_label',
    'non_neg_3_label',
  };

  final _controller = StreamController<void>.broadcast();

  /// Fires when a merge changed a setting, so the UI can re-read it.
  Stream<void> get changes => _controller.stream;

  Isar get _db => IsarService.instance.db;

  /// Mirrors one preference into a row. Called after the setting is written.
  Future<void> capture(SharedPreferences prefs, String key) async {
    if (!syncedKeys.contains(key)) return;
    final raw = prefs.get(key);
    if (raw == null) return;

    final existing = await _db.appSettings.filter().uidEqualTo(key).findFirst();
    final encoded = jsonEncode(raw);
    if (existing != null && existing.value == encoded) return;

    final row = existing ?? (AppSetting()..uid = key);
    row
      ..value = encoded
      ..deletedAt = null
      ..updatedAt = DateTime.now();
    await _db.writeTxn(() async => _db.appSettings.put(row));
  }

  /// Seeds rows for any synced key that has a value but no row yet.
  ///
  /// Runs at startup so a device that has been used for months before sync was
  /// switched on still has something to push.
  Future<void> captureExisting(SharedPreferences prefs) async {
    for (final key in syncedKeys) {
      await capture(prefs, key);
    }
  }

  /// Writes merged rows back into SharedPreferences.
  ///
  /// Returns true when something actually changed, so callers can avoid
  /// rebuilding the settings UI on every no-op sync.
  Future<bool> hydrate(SharedPreferences prefs) async {
    final rows = await _db.appSettings.filter().deletedAtIsNull().findAll();
    var changed = false;

    for (final row in rows) {
      if (!syncedKeys.contains(row.uid)) continue;
      final dynamic decoded;
      try {
        decoded = jsonDecode(row.value);
      } catch (_) {
        continue;
      }
      if (prefs.get(row.uid) == decoded) continue;

      if (decoded is bool) {
        await prefs.setBool(row.uid, decoded);
      } else if (decoded is int) {
        await prefs.setInt(row.uid, decoded);
      } else if (decoded is double) {
        await prefs.setDouble(row.uid, decoded);
      } else if (decoded is String) {
        await prefs.setString(row.uid, decoded);
      } else if (decoded is List) {
        await prefs.setStringList(
          row.uid,
          decoded.map((item) => item.toString()).toList(),
        );
      } else {
        continue;
      }
      changed = true;
    }

    if (changed && !_controller.isClosed) _controller.add(null);
    return changed;
  }

  Future<void> dispose() => _controller.close();
}
