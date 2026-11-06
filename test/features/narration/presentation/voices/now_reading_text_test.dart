import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/domain/audio/speech_audio.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_profile.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/accent_names.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_voice_face.dart';
import 'package:sinapsis/features/narration/presentation/voices/now_reading_text.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_texts.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_audio.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// Cómo se nombra la voz que suena (F46, paso 5f): una sola forma en una
/// frase —la del reproductor—, y el «Voz 2» solo en la lista, con su número
/// de verdad.
void main() {
  final es = AppLocalizationsEs();
  const first = NarrationVoice(name: 'es-us-x-esc-local', locale: 'es-US');
  const second = NarrationVoice(name: 'es-us-x-esd-local', locale: 'es-US');
  const monica = NarrationVoice(name: 'Mónica', locale: 'es-ES');
  final accent = accentDisplayName('es-US');

  group('«Lee ahora»', () {
    test('sin voz, la del teléfono', () {
      expect(
        nowReadingText(es, null, unchosen: true),
        es.f47P3NowReadingSystem,
      );
      expect(
        nowReadingText(es, null, unchosen: false),
        es.f47P3NowReadingSystem,
      );
    });

    test('una del teléfono con código, por su acento —como el reproductor— '
        'y nunca «Voz 1»', () {
      expect(readAloudVoiceName(second, es), accent);
      expect(
        nowReadingText(es, second, unchosen: false),
        es.f47P3NowReading(accent),
      );
      expect(
        nowReadingText(es, second, unchosen: true),
        es.f46P5fNowReadingUnchosen(accent),
      );
      expect(
        nowReadingText(es, second, unchosen: true),
        isNot(contains(es.readAloudVoiceNumber(1))),
      );
    });

    test('una con nombre, por su nombre', () {
      expect(
        nowReadingText(es, monica, unchosen: false),
        es.f47P3NowReading('Mónica'),
      );
    });
  });

  test('el audio descargado nombra la voz como el reproductor', () {
    expect(documentAudioVoicesLabel(es, const [second], const []), accent);
    expect(
      documentAudioVoicesLabel(es, const [second, monica], const []),
      es.f47P5VoicesTwo(accent, 'Mónica'),
    );
    expect(
      documentAudioVoicesLabel(es, const [null], const []),
      es.f47P5PhoneVoice,
    );
    // Y si faltó al generarlo, lo mismo.
    expect(
      documentAudioFailureText(
        es,
        SpeechAudioException(
          SpeechAudioFailure.voiceMissing,
          voiceId: SpeechVoiceIds.device(locale: 'es-US', name: second.name),
        ),
        const [],
      ),
      es.f47P5FailVoice(accent),
    );
  });

  group('el número, solo el de la lista', () {
    test('fuera de la lista, una con código no tiene número: se la nombra por '
        'su acento, y su cara dice el acento', () {
      final profile = voiceProfileOf(second)!;
      expect(profile.number, isNull);
      expect(voiceName(profile, es), accent);
      expect(profile.label, 'es-US');
    });

    test('en la lista, cada una con su número entre las de su acento', () {
      final listed = deviceVoiceProfiles(const [second, first, monica]);
      final numbers = {for (final p in listed) p.voice.name: p.number};
      expect(numbers, {
        'es-us-x-esc-local': 1,
        'es-us-x-esd-local': 2,
        'Mónica': null,
      });
      expect(
        voiceName(listed.firstWhere((p) => p.voice == second), es),
        es.readAloudVoiceNumber(2),
      );
    });

    test('una voz elegida se nombra con su tarjeta de la lista —su número—, '
        'y su cara es la misma dentro y fuera de la lista', () {
      final library = deviceVoiceProfiles(const [first, second]);
      final profile = libraryVoiceProfileOf(second, library)!;
      expect(profile.number, 2);
      expect(voiceName(profile, es), es.readAloudVoiceNumber(2));
      // Fuera de la lista, la que arma la voz misma.
      final alone = libraryVoiceProfileOf(second, const [])!;
      expect(alone.number, isNull);
      expect(alone.id, profile.id);
      // La cara no depende del número: es la de la voz.
      expect(profile.label, alone.label);
      expect(profile.faceKey, alone.faceKey);
    });
  });
}
