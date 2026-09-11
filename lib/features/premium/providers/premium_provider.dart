import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/sync/account_service.dart';
import '../../../core/sync/sync_service.dart';

/// Live account identity and entitlement.
final accountProvider = StreamProvider<AccountState>((ref) {
  return AccountService.instance.changes;
});

/// Entitlement as a plain bool, for the many places that only need the gate.
///
/// Reads through to the service's current value while the stream is still
/// warming up, so a feature is never briefly locked on a cold frame for a user
/// who has already paid.
final isPremiumProvider = Provider<bool>((ref) {
  final account = ref.watch(accountProvider);
  return account.valueOrNull?.isPremium ?? AccountService.instance.state.isPremium;
});

/// True when a backend is compiled into this build at all.
final syncAvailableProvider = Provider<bool>((ref) {
  final account = ref.watch(accountProvider);
  return account.valueOrNull?.isConfigured ??
      AccountService.instance.state.isConfigured;
});

final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  return SyncService.instance.changes;
});
