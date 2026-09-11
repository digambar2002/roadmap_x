import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../providers/premium_provider.dart';

/// Account status, on the home page where people look for it.
///
/// Signing in used to be reachable only through Settings, several taps from
/// anywhere. Showing it here also makes the state legible at a glance: whether
/// there is an account at all, and whether it is activated.
class AccountButton extends ConsumerWidget {
  const AccountButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final account = ref.watch(accountProvider).valueOrNull;
    final isAvailable = ref.watch(syncAvailableProvider);
    final isPremium = ref.watch(isPremiumProvider);
    final email = account?.email ?? '';
    final signedIn = account?.isSignedIn ?? false;

    final String tooltip;
    if (!isAvailable) {
      tooltip = 'Sync unavailable in this build';
    } else if (!signedIn) {
      tooltip = 'Sign in to sync your devices';
    } else if (isPremium) {
      tooltip = 'Premium active — $email';
    } else {
      tooltip = 'Signed in as $email';
    }

    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => context.push('/premium'),
        child: Container(
          height: 38,
          width: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.outline),
            color: cs.surfaceContainerHighest,
          ),
          child: signedIn
              ? _Initial(email: email, isPremium: isPremium)
              : Icon(Icons.person_outline_rounded,
                  size: 20, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _Initial extends StatelessWidget {
  const _Initial({required this.email, required this.isPremium});

  final String email;
  final bool isPremium;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final letter = email.isEmpty ? '?' : email.characters.first.toUpperCase();

    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          letter,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: cs.primary,
          ),
        ),
        // A small dot rather than a second icon: it marks activation without
        // competing with the two action buttons beside it.
        if (isPremium)
          Positioned(
            right: 2,
            bottom: 2,
            child: Container(
              height: 8,
              width: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF34D399),
                border: Border.all(color: cs.surfaceContainerHighest, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}
