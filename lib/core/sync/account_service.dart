import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_config.dart';

/// Snapshot of who is signed in and whether they are entitled to sync.
class AccountState {
  const AccountState({
    required this.isConfigured,
    required this.isSignedIn,
    required this.isPremium,
    this.email,
    this.userId,
    this.isBusy = false,
    this.error,
  });

  const AccountState.unavailable()
      : isConfigured = false,
        isSignedIn = false,
        isPremium = false,
        email = null,
        userId = null,
        isBusy = false,
        error = null;

  final bool isConfigured;
  final bool isSignedIn;
  final bool isPremium;
  final String? email;
  final String? userId;
  final bool isBusy;
  final String? error;

  /// Sync may run only for a signed-in account that has been activated.
  bool get canSync => isConfigured && isSignedIn && isPremium;

  AccountState copyWith({
    bool? isConfigured,
    bool? isSignedIn,
    bool? isPremium,
    String? email,
    String? userId,
    bool? isBusy,
    String? error,
    bool clearError = false,
  }) {
    return AccountState(
      isConfigured: isConfigured ?? this.isConfigured,
      isSignedIn: isSignedIn ?? this.isSignedIn,
      isPremium: isPremium ?? this.isPremium,
      email: email ?? this.email,
      userId: userId ?? this.userId,
      isBusy: isBusy ?? this.isBusy,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Account identity and premium entitlement.
///
/// Entitlement is a boolean on the server's `profiles` row, flipped by hand
/// from the Supabase dashboard after someone pays. The client only *reads* it:
/// the RLS policies in `supabase/schema.sql` gate the sync table on the same
/// flag, so a patched build that forces [isPremium] true locally still gets
/// nothing back from the server.
class AccountService {
  AccountService._();
  static final AccountService instance = AccountService._();

  static const _premiumCacheKey = 'premium_entitlement_cached';

  SharedPreferences? _prefs;
  bool _initialized = false;
  StreamSubscription<AuthState>? _authSub;

  final _controller = StreamController<AccountState>.broadcast();
  Stream<AccountState> get changes => _controller.stream;

  AccountState _state = const AccountState.unavailable();
  AccountState get state => _state;

  bool get isReady => _initialized;
  SupabaseClient get client => Supabase.instance.client;
  User? get _user => _initialized ? client.auth.currentUser : null;

  Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    if (!SyncConfig.isConfigured) {
      // No backend wired up: the app is local-only and says so, rather than
      // failing at the first request.
      _emit(const AccountState.unavailable());
      return;
    }

    try {
      await Supabase.initialize(
        url: SyncConfig.supabaseUrl,
        anonKey: SyncConfig.supabaseAnonKey,
      );
      _initialized = true;
    } catch (error) {
      _emit(
        _state.copyWith(
          isConfigured: true,
          error: 'Could not reach the sync service: $error',
        ),
      );
      return;
    }

    // The cached flag keeps premium features working offline; the server is
    // re-checked below and on every foreground.
    final cachedPremium = _prefs?.getBool(_premiumCacheKey) ?? false;
    _emit(
      AccountState(
        isConfigured: true,
        isSignedIn: _user != null,
        isPremium: _user != null && cachedPremium,
        email: _user?.email,
        userId: _user?.id,
      ),
    );

    _authSub = client.auth.onAuthStateChange.listen((event) async {
      final user = event.session?.user;
      if (user == null) {
        await _cachePremium(false);
        _emit(
          const AccountState(
            isConfigured: true,
            isSignedIn: false,
            isPremium: false,
          ),
        );
        return;
      }
      _emit(
        _state.copyWith(
          isSignedIn: true,
          email: user.email,
          userId: user.id,
          clearError: true,
        ),
      );
      await refreshEntitlement();
    });

    if (_user != null) await refreshEntitlement();
  }

  /// Creates an account. Returns true when the user is signed in straight
  /// away, false when Supabase wants the email confirmed first (the user is
  /// told to check their inbox), and null on failure ([AccountState.error]).
  Future<bool?> signUp(String email, String password) async {
    AuthResponse? response;
    final ok = await _guard(() async {
      response =
          await client.auth.signUp(email: email.trim(), password: password);
    });
    if (!ok) return null;
    return response?.session != null;
  }

  /// Emails a password-reset link. Returns false on failure.
  Future<bool> sendPasswordReset(String email) => _guard(
        () => client.auth.resetPasswordForEmail(
          email.trim(),
          redirectTo: SyncConfig.oauthRedirectUri,
        ),
      );

  void clearError() => _emit(_state.copyWith(clearError: true));

  Future<void> signIn(String email, String password) => _guard(
        () => client.auth.signInWithPassword(
          email: email.trim(),
          password: password,
        ),
      );

  /// Opens Google's consent page in the browser; the session arrives through
  /// the deep link in [SyncConfig.oauthRedirectUri] and is picked up by
  /// `onAuthStateChange`, so nothing else needs to happen here.
  Future<void> signInWithGoogle() => _guard(() async {
        final isMobile = defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS;
        final launched = await client.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: isMobile ? SyncConfig.oauthRedirectUri : null,
          authScreenLaunchMode: isMobile
              ? LaunchMode.externalApplication
              : LaunchMode.platformDefault,
        );
        if (!launched) {
          throw const AuthException('Could not open the Google sign-in page.');
        }
      });

  /// Signing out stops sync but never touches local data — the device keeps
  /// everything it has and carries on working offline.
  Future<void> signOut() => _guard(() => client.auth.signOut());

  /// Runs an auth call, tracking busy state. Returns whether it succeeded;
  /// on failure [AccountState.error] holds a message fit to show the user.
  Future<bool> _guard(Future<void> Function() action) async {
    if (!_initialized) return false;
    _emit(_state.copyWith(isBusy: true, clearError: true));
    try {
      await action();
      _emit(_state.copyWith(isBusy: false));
      return true;
    } on AuthException catch (error) {
      _emit(_state.copyWith(
          isBusy: false, error: friendlyAuthError(error.message)));
      return false;
    } catch (error) {
      _emit(_state.copyWith(
        isBusy: false,
        error: friendlyAuthError(error.toString()),
      ));
      return false;
    }
  }

  /// Re-reads the premium flag. Returns the entitlement actually in force.
  ///
  /// A network failure leaves the cached value alone: losing signal should not
  /// lock a paying user out of features they have already paid for.
  Future<bool> refreshEntitlement() async {
    final user = _user;
    if (user == null) {
      await _cachePremium(false);
      _emit(_state.copyWith(isPremium: false));
      return false;
    }

    try {
      final row = await client
          .from(SyncConfig.profilesTable)
          .select('is_premium, premium_until')
          .eq('id', user.id)
          .maybeSingle();

      final active = row != null && row['is_premium'] == true;
      final until = DateTime.tryParse((row?['premium_until'] ?? '').toString());
      final entitled =
          active && (until == null || until.isAfter(DateTime.now()));

      await _cachePremium(entitled);
      _emit(_state.copyWith(isPremium: entitled, clearError: true));
      return entitled;
    } catch (_) {
      return _state.isPremium;
    }
  }

  Future<void> _cachePremium(bool value) async {
    await _prefs?.setBool(_premiumCacheKey, value);
  }

  void _emit(AccountState next) {
    _state = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  Future<void> dispose() async {
    await _authSub?.cancel();
    await _controller.close();
  }
}

/// Supabase's auth messages, in words a user understands.
String friendlyAuthError(String raw) {
  final m = raw.toLowerCase();
  if (m.contains('invalid login credentials') ||
      m.contains('invalid_credentials')) {
    return 'Wrong email or password.';
  }
  if (m.contains('already registered') || m.contains('already exists')) {
    return 'An account with this email already exists. Sign in instead.';
  }
  if (m.contains('email not confirmed')) {
    return 'Confirm your email first: check your inbox for the link.';
  }
  if (m.contains('password should be') || m.contains('weak password')) {
    return 'Choose a stronger password (at least 6 characters).';
  }
  if (m.contains('unable to validate email') || m.contains('invalid email')) {
    return 'That email address doesn\'t look right.';
  }
  if (m.contains('rate limit') || m.contains('too many') || m.contains('429')) {
    return 'Too many attempts. Wait a minute and try again.';
  }
  if (m.contains('socket') ||
      m.contains('network') ||
      m.contains('failed host lookup')) {
    return 'No internet connection.';
  }
  if (m.contains('google sign-in page')) return raw;
  return 'Something went wrong. Please try again.';
}
