import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';

void main() {
  group('el catálogo de voces sin conexión (F47, paso 3)', () {
    final catalog = OfflineVoiceCatalog.voices;

    test('cada voz es única, y su paquete está en la lista con su tamaño y su '
        'huella', () {
      expect(catalog.map((v) => v.id).toSet(), hasLength(catalog.length));
      for (final voice in catalog) {
        expect(OfflineVoiceCatalog.packages, contains(voice.package));
        expect(voice.package.bytes, greaterThan(10 * 1024 * 1024));
        expect(voice.package.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      }
      expect(
        OfflineVoiceCatalog.packages.map((p) => p.id).toSet(),
        hasLength(OfflineVoiceCatalog.packages.length),
      );
    });

    test('se bajan de la versión tts-models de sherpa-onnx', () {
      final daniela = OfflineVoiceCatalog.byId(
        'vits-piper-es_AR-daniela-high#0',
      )!;
      expect(
        daniela.package.url,
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
        'vits-piper-es_AR-daniela-high.tar.bz2',
      );
      expect(daniela.package.bytes, 115562134);
      expect(daniela.locale, 'es-AR');
      expect(daniela.quality, VoiceQuality.high);
      expect(
        daniela.sampleUrl,
        'https://k2-fsa.github.io/sherpa/onnx/tts/all/piper/mp3/es_AR/'
        'vits-piper-es_AR-daniela-high/0.mp3',
      );
    });

    test('en español, de Argentina, España y México; y Kokoro suma inglés, '
        'francés, italiano, portugués e hindi', () {
      final accents = {for (final voice in catalog) voice.locale};
      expect(accents, containsAll(['es-AR', 'es-ES', 'es-MX']));
      final kokoro = [
        for (final voice in catalog)
          if (voice.package == OfflineVoiceCatalog.kokoro) voice,
      ];
      expect(
        {for (final voice in kokoro) voice.language},
        {'en', 'es', 'fr', 'it', 'pt', 'hi'},
      );
      // Una sola descarga para todas las voces de Kokoro, cada una con su
      // hablante.
      expect(kokoro.map((v) => v.speakerId).toSet(), hasLength(kokoro.length));
    });

    test('el género, solo donde el modelo lo dice', () {
      final sharvard = [
        for (final voice in catalog)
          if (voice.package.id == 'vits-piper-es_ES-sharvard-medium') voice,
      ];
      expect(
        {for (final v in sharvard) v.speakerId: v.gender},
        {0: VoiceGender.male, 1: VoiceGender.female},
      );
      expect(
        OfflineVoiceCatalog.byId('vits-piper-es_AR-daniela-high#0')!.gender,
        isNull,
      );
      expect(
        OfflineVoiceCatalog.byId('kokoro-int8-multi-lang-v1_0#28')!.gender,
        VoiceGender.female,
      );
    });

    test(
      'Kokoro pronuncia el inglés con su léxico y el resto con espeak-ng',
      () {
        final heart = OfflineVoiceCatalog.byId(
          'kokoro-int8-multi-lang-v1_0#3',
        )!;
        final emma = OfflineVoiceCatalog.byId(
          'kokoro-int8-multi-lang-v1_0#21',
        )!;
        final dora = OfflineVoiceCatalog.byId(
          'kokoro-int8-multi-lang-v1_0#28',
        )!;
        final siwis = OfflineVoiceCatalog.byId(
          'kokoro-int8-multi-lang-v1_0#30',
        )!;
        expect(heart.kokoroPhonemes!.lexicon, 'lexicon-us-en.txt');
        expect(emma.kokoroPhonemes!.lexicon, 'lexicon-gb-en.txt');
        expect(dora.kokoroPhonemes!.espeakVoice, 'es');
        expect(siwis.kokoroPhonemes!.espeakVoice, 'fr-fr');
        // Las muestras publicadas de Kokoro no están en su idioma.
        expect(dora.sampleUrl, isNull);
      },
    );

    test('sin GLaDOS ni japonés', () {
      expect(catalog.where((v) => v.package.id.contains('glados')), isEmpty);
      expect(catalog.where((v) => v.language == 'ja'), isEmpty);
    });
  });
}
