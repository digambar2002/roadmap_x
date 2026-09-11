import 'dart:async';

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

  Future<void> signUp(String email, String password) =>
      _guard(() => client.auth.signUp(email: email.trim(), password: password));

  Future<void> signIn(String email, String password) => _guard(
        () => client.auth.signInWithPassword(
          email: email.trim(),
          password: password,
        ),
      );

  /// Signing out stops sync but never touches local data — the device keeps
  /// everything it has and carries on working offline.
  Future<void> signOut() => _guard(() => client.auth.signOut());

  Future<void> _guard(Future<void> Function() action) async {
    if (!_initialized) return;
    _emit(_state.copyWith(isBusy: true, clearError: true));
    try {
      await action();
      _emit(_state.copyWith(isBusy: false));
    } on AuthException catch (error) {
      _emit(_state.copyWith(isBusy: false, error: error.message));
    } catch (error) {
      _emit(_state.copyWith(isBusy: false, error: error.toString()));
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
      final entitled = active && (until == null || until.isAfter(DateTime.now()));

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
