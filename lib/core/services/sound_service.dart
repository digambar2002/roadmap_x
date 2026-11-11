import 'dart:async';
import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every sound the app makes. The files are synthesised originals in
/// `assets/sounds/`.
enum Sfx {
  pat,
  eat,
  drink,
  play,
  wash,
  coin,
  sparkle,
  done,
  fanfare,
  whimper,
  nope,
}

/// Short sound effects, kept polite:
///
/// - They mix with whatever else is playing instead of pausing the user's
///   music or podcast.
/// - They respect the phone's silent switch on iOS and media volume on
///   Android.
/// - One switch in Settings turns them all off.
class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  static const enabledKey = 'sound_effects_enabled';

  final _pools = <Sfx, AudioPool>{};
  bool _enabled = true;
  bool _ready = false;

  bool get enabled => _enabled;

  static bool get _supported =>
      !kIsWeb &&
      !Platform.environment.containsKey('FLUTTER_TEST') &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// Preloads every sound so the first play is instant. Safe to call more
  /// than once; failures leave the app silent rather than broken.
  Future<void> init(SharedPreferences prefs) async {
    _enabled = prefs.getBool(enabledKey) ?? true;
    if (_ready || !_supported) return;
    try {
      final context = AudioContextConfig(
        focus: AudioContextConfigFocus.mixWithOthers,
        respectSilence: true,
      ).build();
      for (final sfx in Sfx.values) {
        _pools[sfx] = await AudioPool.create(
          source: AssetSource('sounds/${sfx.name}.wav'),
          maxPlayers: 3,
          audioContext: context,
          playerMode: PlayerMode.lowLatency,
        );
      }
      _ready = true;
    } catch (e) {
      debugPrint('Sound effects unavailable: $e');
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledKey, value);
    if (value) play(Sfx.done);
  }

  /// Fire and forget. Never throws and never waits.
  void play(Sfx sfx, {double volume = 1.0}) {
    if (!_enabled || !_ready) return;
    final pool = _pools[sfx];
    if (pool == null) return;
    unawaited(pool.start(volume: volume).then((_) {}).catchError((Object _) {}));
  }
}
