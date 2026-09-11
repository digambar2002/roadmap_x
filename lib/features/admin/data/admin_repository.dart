import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/sync/account_service.dart';
import '../../../core/sync/sync_config.dart';

/// One account as the admin screen sees it.
class AdminAccount {
  const AdminAccount({
    required this.id,
    required this.email,
    required this.isPremium,
    required this.premiumUntil,
    required this.note,
    required this.createdAt,
  });

  factory AdminAccount.fromRow(Map<String, dynamic> row) => AdminAccount(
        id: (row['id'] ?? '').toString(),
        email: (row['email'] ?? '').toString(),
        isPremium: row['is_premium'] == true,
        premiumUntil:
            DateTime.tryParse((row['premium_until'] ?? '').toString()),
        note: (row['note'] ?? '').toString(),
        createdAt: DateTime.tryParse((row['created_at'] ?? '').toString()),
      );

  final String id;
  final String email;
  final bool isPremium;

  /// null with [isPremium] true means no expiry.
  final DateTime? premiumUntil;
  final String note;
  final DateTime? createdAt;

  bool get hasExpired =>
      isPremium && premiumUntil != null && premiumUntil!.isBefore(DateTime.now());

  /// Matches `public.is_premium()` — the predicate the sync policies apply.
  bool get isActive => isPremium && !hasExpired;

  int? get daysRemaining {
    final until = premiumUntil;
    if (!isActive || until == null) return null;
    return until.difference(DateTime.now()).inDays;
  }
}

/// Reads and edits other people's entitlement.
///
/// Everything here is ordinary authenticated access: the server decides what
/// an admin may do, via `public.is_admin()` in the RLS policies and inside
/// `grant_premium()`. There is no service-role key in the app — one would
/// bypass every policy and is unsafe to ship in a client at all.
class AdminRepository {
  AdminRepository._();
  static final AdminRepository instance = AdminRepository._();

  SupabaseClient get _client => AccountService.instance.client;

  /// Whether the signed-in account may administer others.
  Future<bool> isAdmin() async {
    final account = AccountService.instance.state;
    if (!account.isConfigured || !account.isSignedIn) return false;
    try {
      final row = await _client
          .from('admins')
          .select('user_id')
          .eq('user_id', account.userId!)
          .maybeSingle();
      return row != null;
    } catch (_) {
      // A policy refusal reads as "not an admin" rather than an error state.
      return false;
    }
  }

  Future<List<AdminAccount>> listAccounts() async {
    final rows = await _client
        .from(SyncConfig.profilesTable)
        .select('id, email, is_premium, premium_until, note, created_at')
        .order('created_at', ascending: false);
    return rows
        .map((row) => AdminAccount.fromRow(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// Grants [months] of premium, or revokes when [months] is 0.
  ///
  /// The arithmetic lives in the database function: granting a month to
  /// someone with two weeks left extends to six weeks rather than resetting to
  /// four, and doing that server-side keeps two admins acting at once from
  /// silently shortening a subscription.
  Future<AdminAccount> grantPremium(String email, int months) async {
    final result = await _client.rpc<List<dynamic>>(
      'grant_premium',
      params: {'target_email': email, 'months': months},
    );
    if (result.isEmpty) {
      throw StateError('No account for $email');
    }
    return AdminAccount.fromRow(
      Map<String, dynamic>.from(result.first as Map),
    );
  }
}
