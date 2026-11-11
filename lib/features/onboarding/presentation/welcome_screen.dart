import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/layout/adaptive_page.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/services/onboarding.dart';
import '../../../core/services/shared_preferences_provider.dart';
import '../../../core/sync/account_service.dart';
import '../../premium/providers/premium_provider.dart';
import '../../settings/providers/settings_provider.dart';

/// First-run walkthrough: three short slides, then a name and an optional
/// account. Finishing it marks onboarding complete, after which the app opens
/// straight to the dashboard on every launch.
///
/// Signing in here, before anything local exists, is still the cleanest
/// moment to do it: the account's data arrives with nothing to merge. But it
/// is an offer, not a question the user has to understand to get in.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _pages = PageController();
  final _name = TextEditingController();
  int _index = 0;
  bool _finishing = false;

  static const _slides = [
    _Slide(
      icon: Icons.flag_rounded,
      title: 'Goals that go somewhere',
      body: 'Set a goal, break it into milestones, and turn each milestone '
          'into tasks you can actually tick off.',
    ),
    _Slide(
      icon: Icons.local_fire_department_rounded,
      title: 'Habits and a daily rhythm',
      body: 'Track daily habits, plan your week, and get a reminder at the '
          'moment it helps.',
    ),
    _Slide(
      icon: Icons.insights_rounded,
      title: 'See the progress',
      body: 'Streaks, focus views and a daily briefing keep the big picture '
          'in sight. Everything works offline, on this device.',
    ),
  ];

  int get _lastIndex => _slides.length; // the set-up page

  @override
  void dispose() {
    _pages.dispose();
    _name.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    _pages.animateToPage(
      index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _saveName() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    await ref.read(sharedPreferencesProvider).setString('user_name', name);
    // The settings notifier may already hold the default; make it re-read.
    ref.invalidate(settingsProvider);
  }

  Future<void> _finish({String? then}) async {
    if (_finishing) return;
    _finishing = true;
    await _saveName();
    await Onboarding.markComplete(ref.read(sharedPreferencesProvider));
    if (!mounted) return;
    context.go('/today');
    if (then != null) context.push(then);
  }

  Future<void> _continueWithGoogle() async {
    await _saveName();
    await AccountService.instance.signInWithGoogle();
    // The session lands through the deep link; the listener in build() takes
    // it from there. Nothing else to do here.
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final syncAvailable = ref.watch(syncAvailableProvider);

    // A sign-in started from this screen completes in the browser; when the
    // session arrives, let the user straight in.
    ref.listen(accountProvider, (previous, next) {
      final signedIn = next.valueOrNull?.isSignedIn ?? false;
      final wasSignedIn = previous?.valueOrNull?.isSignedIn ?? false;
      if (signedIn && !wasSignedIn) _finish();
    });

    final onLast = _index == _lastIndex;

    return Scaffold(
      backgroundColor: cs.surface,
      body: AdaptivePage(
        child: SafeArea(
          child: Column(
            children: [
              // Top bar: skip on the slides, nothing on the set-up page.
              SizedBox(
                height: 48,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: AnimatedOpacity(
                    opacity: onLast ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: TextButton(
                      onPressed: onLast ? null : () => _goTo(_lastIndex),
                      child: const Text('Skip'),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pages,
                  onPageChanged: (i) => setState(() => _index = i),
                  children: [
                    for (final slide in _slides) _SlidePage(slide: slide),
                    _SetupPage(
                      nameController: _name,
                      syncAvailable: syncAvailable,
                      onGoogle: _continueWithGoogle,
                      onEmail: () => _finish(then: '/premium'),
                      onSkipAccount: _finish,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  context.pageGutter,
                  8,
                  context.pageGutter,
                  16,
                ),
                child: Row(
                  children: [
                    _Dots(count: _lastIndex + 1, index: _index),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: !onLast
                            ? FilledButton.icon(
                                onPressed: () => _goTo(_index + 1),
                                icon: const Icon(Icons.arrow_forward_rounded,
                                    size: 18),
                                label: const Text('Next'),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 14,
                                  ),
                                ),
                              )
                            : Text(
                                'You can sign in any time from Settings.',
                                textAlign: TextAlign.end,
                                style: tt.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Slide {
  const _Slide({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;
}

class _SlidePage extends StatelessWidget {
  const _SlidePage({required this.slide});
  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding:
          EdgeInsets.symmetric(horizontal: context.pageGutter, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(slide.icon, size: 64, color: cs.primary),
          ).animate().scale(
                begin: const Offset(0.85, 0.85),
                duration: 400.ms,
                curve: Curves.easeOutBack,
              ),
          const SizedBox(height: 36),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ).animate().fadeIn(delay: 80.ms).slideY(begin: 0.1),
          const SizedBox(height: 12),
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
          ).animate().fadeIn(delay: 160.ms).slideY(begin: 0.1),
        ],
      ),
    );
  }
}

class _SetupPage extends StatelessWidget {
  const _SetupPage({
    required this.nameController,
    required this.syncAvailable,
    required this.onGoogle,
    required this.onEmail,
    required this.onSkipAccount,
  });

  final TextEditingController nameController;
  final bool syncAvailable;
  final VoidCallback onGoogle;
  final VoidCallback onEmail;
  final VoidCallback onSkipAccount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding:
          EdgeInsets.symmetric(horizontal: context.pageGutter, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset(
                'assets/icon/app_icon.png',
                width: 88,
                height: 88,
                errorBuilder: (_, __, ___) =>
                    const Text('🧭', style: TextStyle(fontSize: 56)),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Welcome to RoadmapX',
            textAlign: TextAlign.center,
            style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'What should we call you?',
            textAlign: TextAlign.center,
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: nameController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSkipAccount(),
            decoration: const InputDecoration(
              labelText: 'Your name',
              hintText: 'Optional',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: onSkipAccount,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Get started'),
          ),
          if (syncAvailable) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: Divider(color: cs.outlineVariant)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'or sync across devices',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                Expanded(child: Divider(color: cs.outlineVariant)),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onGoogle,
              icon: const Icon(Icons.g_mobiledata_rounded, size: 26),
              label: const Text('Continue with Google'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onEmail,
              icon: const Icon(Icons.mail_outline_rounded, size: 20),
              label: const Text('Sign in with email'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Signing in now brings an existing account\'s goals and habits '
              'to this device. Sync is part of RoadmapX Premium.',
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.only(right: 6),
            width: i == index ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == index ? cs.primary : cs.outlineVariant,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}
