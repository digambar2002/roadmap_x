import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../premium/providers/premium_provider.dart';
import '../data/admin_repository.dart';

final adminRepositoryProvider = Provider<AdminRepository>(
  (_) => AdminRepository.instance,
);

/// Whether the signed-in account may administer others.
///
/// Re-evaluated whenever the account changes, so signing out hides the screen
/// without needing a restart.
final isAdminProvider = FutureProvider<bool>((ref) async {
  ref.watch(accountProvider);
  return ref.read(adminRepositoryProvider).isAdmin();
});

final adminAccountsProvider = FutureProvider<List<AdminAccount>>((ref) async {
  final isAdmin = await ref.watch(isAdminProvider.future);
  if (!isAdmin) return const <AdminAccount>[];
  return ref.read(adminRepositoryProvider).listAccounts();
});
