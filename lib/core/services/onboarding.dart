import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/isar_service.dart';
import '../models/models.dart';

/// First-run state.
///
/// The welcome screen exists to head off a merge problem rather than to
/// decorate the launch: someone who starts using the app, then signs in to an
/// account that already has data, ends up with both sets side by side. Asking
/// which they meant *before* they create anything avoids it entirely.
class Onboarding {
  const Onboarding._();

  static const String completedKey = 'onboarding_completed';

  static bool isComplete(SharedPreferences prefs) =>
      prefs.getBool(completedKey) ?? false;

  static Future<void> markComplete(SharedPreferences prefs) =>
      prefs.setBool(completedKey, true);

  /// Marks onboarding done for anyone who already has data.
  ///
  /// Existing users are upgrading into this screen, not arriving at it; the
  /// question is meaningless once there is a database to answer it for.
  static Future<void> skipForExistingUsers(SharedPreferences prefs) async {
    if (isComplete(prefs)) return;
    final db = IsarService.instance.db;
    // Separate statements rather than one chained expression: the query
    // builder's type only resolves once each call is its own await.
    final goals = await db.goals.filter().deletedAtIsNull().count();
    final habits = await db.habits.filter().deletedAtIsNull().count();
    final schedule = await db.scheduleItems.filter().deletedAtIsNull().count();

    if (goals > 0 || habits > 0 || schedule > 0) {
      await markComplete(prefs);
    }
  }
}
