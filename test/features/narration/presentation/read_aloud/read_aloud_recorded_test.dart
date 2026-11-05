import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_media_session.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_speed_sheet.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_voice_face.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/fake_speech_track_player.dart';
import '../../../../support/fake_text_to_speech_service.dart';

const _a = NarrationVoice(name: 'a', locale: 'es-AR');
const _b = NarrationVoice(name: 'b', locale: 'es-ES');

/// Un podcast de tres tramos: empiezan en 0, 2 y 5 s, y dura 8 s.
const _podcast = ReadableDocument(
  id: 'podcast:c1',
  title: 'El mar abierto',
  segments: [
    ReadableSegment(sourceKey: 'podcast:c1', start: 0, end: 4, spoken: 'Hola'),
    ReadableSegment(sourceKey: 'podcast:c1', start: 5, end: 9, spoken: 'Chau'),
    ReadableSegment(sourceKey: 'podcast:c1', start: 10, end: 13, spoken: 'Fin'),
  ],
  recording: RecordedSpeech(
    path: '/boveda/podcast.m4a',
    duration: Duration(seconds: 8),
    starts: [Duration.zero, Duration(seconds: 2), Duration(seconds: 5)],
    voices: [_a, _b, _a],
  ),
);

final _text = ReadableDocument(
  id: 'item:1',
  title: 'Un texto',
  segments: buildReadableSegments('Uno dos.\nTres.', sourceKey: 'item:1'),
);

/// F47, paso 6b: un audio ya generado —un podcast— en el lector: suena desde
/// el archivo con su tiempo real, resalta el tramo que suena y su voz, y
/// ±10 s, la barra, la velocidad y la cola funcionan como con la voz.
void main() {
  late FakeTextToSpeechService tts;
  late FakeSpeechTrackPlayer track;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tts = FakeTextToSpeechService();
    track = FakeSpeechTrackPlayer();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        textToSpeechServiceProvider.overrideWithValue(tts),
        speechTrackPlayerProvider.overrideWithValue(track),
      ],
    );
    addTearDown(container.dispose);
  });

  ReadAloudController controller() =>
      container.read(readAloudControllerProvider.notifier);
  ReadAloudState state() => container.read(readAloudControllerProvider);
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  const t = Duration(seconds: 1);

  test('abrirlo hace sonar el archivo, no la voz, con su tiempo real y su '
      'velocidad', () async {
    await controller().setSpeed(1.5);
    await controller().open(_podcast);
    await settle();

    expect(track.calls, [
      'open /boveda/podcast.m4a',
      'speed 1.5',
      'seek 0',
      'play',
    ]);
    expect(tts.spoken, isEmpty);
    expect(state().playing, isTrue);
    expect(state().recording, isNotNull);
    // 8 s a 1,5× se oyen en 5,3 s.
    expect(state().total, const Duration(microseconds: 5333333));
    expect(state().voice, _a);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('sigue lo que suena: el tramo, su voz, el avance y el tiempo', () async {
    await controller().open(_podcast);
    await settle();

    track.advance(t * 2);
    await settle();
    expect(state().segmentIndex, 1);
    expect(state().currentSegment!.spoken, 'Chau');
    expect(state().voice, _b);
    expect(state().elapsed, t * 2);
    expect(state().progress, closeTo(0.25, 1e-9));

    track.advance(const Duration(milliseconds: 3500));
    await settle();
    expect(state().segmentIndex, 2);
    expect(state().voice, _a);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('±10 s, la barra y los tramos van al tiempo real, contado a la '
      'velocidad de ahora', () async {
    await controller().open(_podcast);
    await settle();
    track.advance(t);
    await settle();

    // A 2×, +2 s de lo que se oye son 4 s del audio.
    await controller().setSpeed(2);
    track.calls.clear();
    await controller().skip(t * 2);
    await settle();
    expect(track.calls, ['speed 2.0', 'seek 5000', 'play']);
    expect(state().segmentIndex, 2);

    await controller().seekToSegment(1);
    await settle();
    expect(track.calls.where((c) => c.startsWith('seek')).last, 'seek 2000');

    // Soltar la barra en 1 s de lo que se oye, a 2×: el segundo 2.
    await controller().seekTo(t);
    await settle();
    expect(track.calls.where((c) => c.startsWith('seek')).last, 'seek 2000');

    await controller().seekToFraction(0.5);
    await settle();
    expect(track.calls.where((c) => c.startsWith('seek')).last, 'seek 4000');

    // Antes del principio, el principio.
    await controller().skip(-t * 10);
    await settle();
    expect(track.calls.where((c) => c.startsWith('seek')).last, 'seek 0');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('cambiar la velocidad no corta lo que suena', () async {
    await controller().open(_podcast);
    await settle();
    track.calls.clear();
    await controller().setSpeed(1.2);
    expect(track.calls, ['speed 1.2']);
    expect(tts.spoken, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('pausar y seguir, desde donde iba; en pausa, saltar no lo hace '
      'sonar', () async {
    await controller().open(_podcast);
    await settle();
    track.advance(t * 3);
    await settle();
    await controller().pause();
    expect(state().playing, isFalse);
    expect(track.playing, isFalse);

    track.calls.clear();
    await controller().skip(t);
    await settle();
    expect(track.calls, ['seek 4000']);
    expect(state().playing, isFalse);

    await controller().play();
    await settle();
    expect(track.calls.last, 'play');
    expect(state().playing, isTrue);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('si el audio se pausa solo —una llamada—, el lector lo dice; un '
      'aviso de antes de arrancar no cuenta', () async {
    await controller().open(_podcast);
    await settle();
    // Lo del salto llegó antes de sonar: el reproductor sigue pidiéndolo.
    expect(state().playing, isTrue);

    track.interrupt();
    await settle();
    expect(state().playing, isFalse);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('al terminar queda terminado, o sigue con la cola; pasado el final, '
      'también termina', () async {
    await controller().open(_podcast);
    await settle();
    await controller().enqueue(_text);

    track.finish(const Duration(seconds: 8));
    await settle();
    await settle();
    // Lo que sigue en la cola es un texto: suena con la voz, y el audio se
    // cierra.
    expect(state().document!.id, 'item:1');
    expect(state().recording, isNull);
    expect(tts.spoken, isNotEmpty);
    expect(track.calls, contains('close'));

    await controller().open(_podcast);
    await settle();
    await controller().skip(const Duration(seconds: 30));
    await settle();
    expect(state().finished, isTrue);
    expect(state().elapsed, state().total);
    expect(track.playing, isFalse);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('un archivo que no se puede abrir o que falla a mitad no se finge: el '
      'reproductor lo dice', () async {
    track.broken.add('/boveda/podcast.m4a');
    await controller().open(_podcast);
    await settle();
    expect(state().failed, isTrue);
    expect(state().playing, isFalse);

    track.broken.clear();
    await controller().play();
    await settle();
    expect(state().failed, isFalse);
    track.breakDown();
    await settle();
    expect(state().failed, isTrue);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('elegir otra voz no cambia lo grabado', () async {
    await controller().open(_podcast);
    await settle();
    await controller().setVoice(_b);
    await settle();
    expect(state().voice, _a);
    expect(tts.spoken, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('cerrar lo cierra; un texto después suena con la voz', () async {
    await controller().open(_podcast);
    await settle();
    await controller().close();
    expect(track.calls.last, 'close');
    expect(state().document, isNull);

    await controller().open(_text);
    await settle();
    expect(tts.spoken, isNotEmpty);
    expect(state().recording, isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('en la tarjeta de la notificación se escucha, con la voz del tramo, y '
      'no pide el foco de audio: su reproductor ya lo pide', () async {
    final es = AppLocalizationsEs();
    final source = ReadAloudMediaSource(controller);
    addTearDown(source.dispose);
    await controller().open(_podcast);
    await settle();
    track.advance(const Duration(seconds: 3));
    await settle();

    source.describe(state(), es, 'es');
    final speed = formatReadAloudSpeed(1, 'es');
    var card = source.state.value!;
    expect(card.title, 'El mar abierto');
    expect(
      card.subtitle,
      es.f47P6bListeningWith(readAloudVoiceName(_b, es), speed),
    );
    expect(card.requestsAudioFocus, isFalse);
    expect(card.position, const Duration(seconds: 3));
    expect(card.duration, const Duration(seconds: 8));

    await controller().pause();
    source.describe(state(), es, 'es');
    card = source.state.value!;
    expect(
      card.subtitle,
      es.f47P2PausedWith(readAloudVoiceName(_b, es), speed),
    );

    // Un texto leído con la voz sí lo pide.
    await controller().open(_text);
    await settle();
    source.describe(state(), es, 'es');
    expect(source.state.value!.requestsAudioFocus, isTrue);
    expect(
      source.state.value!.subtitle,
      es.f47P2ReadingWith(readAloudVoiceName(state().voice, es), speed),
    );
  }, timeout: const Timeout(Duration(seconds: 30)));
}
