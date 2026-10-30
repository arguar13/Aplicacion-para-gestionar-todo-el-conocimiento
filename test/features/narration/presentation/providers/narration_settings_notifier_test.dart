import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_settings_notifier.dart';

const _argentina = NarrationVoice(name: 'es-ar-x-local', locale: 'es-AR');
const _english = NarrationVoice(name: 'en-us-x-sfg-local', locale: 'en-US');
const _daniela = NarrationVoice(
  name: 'vits-piper-es_AR-daniela-high#0',
  locale: 'es-AR',
  engine: NarrationEngine.offline,
);

void main() {
  Future<NarrationSettingsNotifier> create([
    Map<String, Object> stored = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(stored);
    return NarrationSettingsNotifier(
      prefs: await SharedPreferences.getInstance(),
    );
  }

  group('una voz por idioma (F47, paso 3, decisión L)', () {
    test('la voz guardada antes de F47 cuenta como la de su idioma', () async {
      final notifier = await create({
        'narration_voice': 'es-ar-x-local\u0000es-AR',
      });
      expect(notifier.state.voice, _argentina);
      expect(notifier.state.voicesByLanguage, {'es': _argentina});
    });

    test('elegir una voz la deja para su idioma, y se recuerda entre '
        'reinicios, también una sin conexión', () async {
      final notifier = await create();
      await notifier.selectVoice(_english);
      await notifier.selectVoice(_daniela);

      final again = NarrationSettingsNotifier(
        prefs: await SharedPreferences.getInstance(),
      );
      expect(again.state.voice, _daniela);
      expect(again.state.voicesByLanguage, {'en': _english, 'es': _daniela});
    });

    test('la del sistema deja sin elegida al idioma que se leía', () async {
      final notifier = await create();
      await notifier.selectVoice(_english);
      await notifier.selectVoice(_argentina);

      await notifier.selectVoice(null, language: 'es');

      expect(notifier.state.voice, isNull);
      expect(notifier.state.voicesByLanguage, {'en': _english});
    });

    test('volver un idioma a la del teléfono', () async {
      final notifier = await create();
      await notifier.selectVoice(_english);
      await notifier.selectVoice(_argentina);

      await notifier.clearLanguage('es');

      expect(notifier.state.voicesByLanguage, {'en': _english});
      expect(notifier.state.voice, isNull);
      final again = NarrationSettingsNotifier(
        prefs: await SharedPreferences.getInstance(),
      );
      expect(again.state.voicesByLanguage, {'en': _english});
    });

    test('lo guardado roto no deja sin voces', () async {
      final notifier = await create({
        'narration_voice': 'es-ar-x-local\u0000es-AR',
        'narration_voices_by_language': '{roto',
      });
      expect(notifier.state.voicesByLanguage, {'es': _argentina});
    });
  });
}
