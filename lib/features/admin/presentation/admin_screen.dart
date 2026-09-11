import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/layout/adaptive_page.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../shared/widgets/empty_state.dart';
import '../data/admin_repository.dart';
import '../providers/admin_provider.dart';

/// Grants and revokes premium for other accounts.
///
/// Visible only to accounts listed in `public.admins`, and the server enforces
/// that independently: every action goes through `grant_premium()`, which
/// re-checks `is_admin()` before it writes. Hiding the screen is convenience,
/// not the security boundary.
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  final _search = TextEditingController();
  String _query = '';
  String? _busyEmail;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _grant(AdminAccount account, int months) async {
    setState(() => _busyEmail = account.email);
    try {
      final updated = await ref
          .read(adminRepositoryProvider)
          .grantPremium(account.email, months);
      ref.invalidate(adminAccountsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            months == 0
                ? 'Revoked ${account.email}'
                : updated.premiumUntil == null
                    ? 'Activated ${account.email}'
                    : 'Active until '
                        '${DateFormat('d MMM yyyy').format(updated.premiumUntil!)}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _busyEmail = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final accountsAsync = ref.watch(adminAccountsProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text('Admin',
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        backgroundColor: cs.surface,
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(adminAccountsProvider),
          ),
        ],
      ),
      body: AdaptivePage(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                context.pageGutter,
                8,
                context.pageGutter,
                8,
              ),
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  hintText: 'Search by email',
                  prefixIcon: Icon(Icons.search_rounded, size: 20),
                ),
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              ),
            ),
            Expanded(
              child: accountsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Padding(
                    padding: EdgeInsets.all(context.pageGutter),
                    child: Text('Could not load accounts.\n\n$error',
                        textAlign: TextAlign.center),
                  ),
                ),
                data: (accounts) {
                  final visible = _query.isEmpty
                      ? accounts
                      : accounts
                          .where((a) => a.email.toLowerCase().contains(_query))
                          .toList();

                  if (visible.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: EdgeInsets.all(context.pageGutter),
                        child: EmptyState(
                          emoji: '👤',
                          title: accounts.isEmpty
                              ? 'No accounts yet'
                              : 'No match',
                          subtitle: accounts.isEmpty
                              ? 'Accounts appear here once someone signs up.'
                              : 'No account matches "$_query".',
                        ),
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () async =>
                        ref.invalidate(adminAccountsProvider),
                    child: ListView.builder(
                      padding: EdgeInsets.fromLTRB(
                        context.pageGutter,
                        0,
                        context.pageGutter,
                        40,
                      ),
                      itemCount: visible.length,
                      itemBuilder: (context, i) => _AccountRow(
                        account: visible[i],
                        isBusy: _busyEmail == visible[i].email,
                        onGrant: (months) => _grant(visible[i], months),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.isBusy,
    required this.onGrant,
  });

  final AdminAccount account;
  final bool isBusy;
  final ValueChanged<int> onGrant;

  /// The periods offered. Each *extends* from whatever is left, so tapping
  /// twice gives two periods rather than one.
  static const _periods = <({String label, int months})>[
    (label: '1 month', months: 1),
    (label: '6 months', months: 6),
    (label: '1 year', months: 12),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final String status;
    final Color statusColor;
    if (account.isActive) {
      final until = account.premiumUntil;
      final days = account.daysRemaining;
      statusColor = const Color(0xFF34D399);
      status = until == null
          ? 'Active — no expiry'
          : 'Active until ${DateFormat('d MMM yyyy').format(until)}'
              '${days != null ? ' · $days days left' : ''}';
    } else if (account.hasExpired) {
      statusColor = cs.error;
      status = 'Expired '
          '${DateFormat('d MMM yyyy').format(account.premiumUntil!)}';
    } else {
      statusColor = cs.onSurfaceVariant;
      status = 'Free';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outline),
          color: cs.surfaceContainerHighest,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    account.email,
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isBusy)
                  const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(status, style: tt.bodySmall?.copyWith(color: statusColor)),
            if (account.note.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(account.note,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final period in _periods)
                  OutlinedButton(
                    onPressed: isBusy ? null : () => onGrant(period.months),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(
                      account.isActive ? '+${period.label}' : period.label,
                    ),
                  ),
                if (account.isPremium)
                  TextButton(
                    onPressed: isBusy ? null : () => onGrant(0),
                    style: TextButton.styleFrom(
                      foregroundColor: cs.error,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Revoke'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
