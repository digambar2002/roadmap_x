import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/local_changes.dart';
import '../../../core/services/synced_settings.dart';
import '../domain/pet_domain.dart';

/// Stores the pet as one JSON setting. It is on the synced-settings list, so
/// the pet, its inventory and the coins spent follow the account to every
/// device and survive a reinstall when sync is on.
class PetRepository {
  PetRepository._();
  static final PetRepository instance = PetRepository._();

  static const key = 'pet_state_v1';

  Future<PetState?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      return PetState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(PetState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(state.toJson()));
    await SyncedSettings.instance.capture(prefs, key);
    // Backup, sync push and the hunger reminder all hang off this.
    await LocalChanges.instance.notify();
  }
}
