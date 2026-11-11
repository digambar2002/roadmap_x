import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:roadmap_x/core/services/sound_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every sound has a file name matching an asset', () {
    expect(Sfx.values.map((s) => s.name), containsAll(
        ['pat', 'eat', 'drink', 'play', 'wash', 'coin', 'done', 'fanfare']));
  });

  test('playing is a safe no-op when audio is unavailable', () async {
    SharedPreferences.setMockInitialValues({});
    await SoundService.instance.init(await SharedPreferences.getInstance());
    for (final sfx in Sfx.values) {
      SoundService.instance.play(sfx);
    }
  });

  test('the on/off switch is remembered', () async {
    SharedPreferences.setMockInitialValues({});
    await SoundService.instance.setEnabled(false);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(SoundService.enabledKey), isFalse);
    expect(SoundService.instance.enabled, isFalse);
    await SoundService.instance.setEnabled(true);
    expect(SoundService.instance.enabled, isTrue);
  });
}
