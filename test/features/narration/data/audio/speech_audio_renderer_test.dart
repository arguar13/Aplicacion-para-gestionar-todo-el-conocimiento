import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/features/narration/data/audio/speech_audio_encoder.dart';
import 'package:sinapsis/features/narration/data/audio/speech_audio_renderer.dart';
import 'package:sinapsis/features/narration/data/audio/speech_wav.dart';
import 'package:sinapsis/features/narration/domain/audio/speech_audio.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

import 'speech_audio_fakes.dart';

/// F47, pasos 5 y 6: la pieza común para generar audio en el teléfono —de
/// tramos con su voz y su pausa a un archivo, retomable, con su avance—.
void main() {
  late Directory root;
  late FakeVoiceRenderer voices;
  late FakeEncoder encoder;
  late FakeDecoder decoder;
  late SpeechAudioRenderer renderer;
  var now = DateTime(2026, 10, 31);

  setUp(() {
    root = Directory.systemTemp.createTempSync('audio');
    voices = FakeVoiceRenderer();
    encoder = FakeEncoder();
    decoder = FakeDecoder();
    now = DateTime(2026, 10, 31);
    renderer = SpeechAudioRenderer(
      voices: () => [voices],
      workRoot: () async => root,
      encoder: encoder,
      decoder: decoder,
      // En el mismo isolate: los dobles no cruzan a otro.
      assemble: (job) async => assembleSpeechWav(job),
      clock: () => now,
    );
  });
  tearDown(() => root.deleteSync(recursive: true));

  const pieces = [
    SpeechAudioPiece(
      text: 'Hola, ¿qué tal?',
      voiceId: 'fake:a',
      pauseAfter: Duration(milliseconds: 550),
    ),
    SpeechAudioPiece(text: 'Todo bien.', voiceId: 'fake:b'),
  ];
  const request = SpeechAudioRequest(workKey: 'podcast-c1', pieces: pieces);

  test('genera cada tramo con su voz, los arma con su pausa y los comprime; '
      'dice cuánto dura y dónde empieza cada tramo', () async {
    final progress = <(int, int)>[];
    final done = await renderer.render(
      request,
      onProgress: (done, total) => progress.add((done, total)),
    );

    expect(voices.said, [
      ('fake:a', 'Hola, ¿qué tal?'),
      ('fake:b', 'Todo bien.'),
    ]);
    expect(done.mimeType, 'audio/mp4');
    expect(done.extension, 'm4a');
    expect(done.path, p.join(root.path, 'podcast-c1', 'audio.m4a'));
    expect(File(done.path).existsSync(), isTrue);
    // El WAV armado se va al comprimirlo.
    expect(
      File(p.join(root.path, 'podcast-c1', 'armado.wav')).existsSync(),
      isFalse,
    );
    // Cada voz de mentira dice 400 ms; con 40 de margen a cada lado son 480,
    // y después de la primera, 550 de pausa.
    expect(done.starts, [
      Duration.zero,
      const Duration(milliseconds: 480 + 550),
    ]);
    expect(done.duration, const Duration(milliseconds: 480 + 550 + 480));
    // El avance: un paso por tramo y uno para el armado.
    expect(progress, [(0, 3), (1, 3), (2, 3), (3, 3)]);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('donde no hay con qué comprimir, queda el WAV', () async {
    encoder.supported = false;
    final done = await renderer.render(request);
    expect(done.mimeType, 'audio/wav');
    expect(done.extension, 'wav');
    expect(p.basename(done.path), 'armado.wav');
    expect(File(done.path).existsSync(), isTrue);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('retomable: lo ya generado no se rehace, y un tramo que cambió se '
      'genera solo él', () async {
    await renderer.render(request);
    expect(voices.said, hasLength(2));

    voices.said.clear();
    await renderer.render(request);
    expect(voices.said, isEmpty);

    await renderer.render(
      const SpeechAudioRequest(
        workKey: 'podcast-c1',
        pieces: [
          SpeechAudioPiece(
            text: 'Hola, ¿qué tal?',
            voiceId: 'fake:a',
            pauseAfter: Duration(milliseconds: 550),
          ),
          SpeechAudioPiece(text: 'Todo muy bien.', voiceId: 'fake:b'),
        ],
      ),
    );
    expect(voices.said, [('fake:b', 'Todo muy bien.')]);

    // Otra versión de la voz es otro audio.
    voices
      ..said.clear()
      ..version = 'v2';
    await renderer.render(request);
    expect(voices.said, hasLength(2));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('cancelado a mitad, lo hecho queda y el próximo intento sigue desde '
      'ahí', () async {
    final signal = CancellationSignal();
    voices.onSay = (voice, _) {
      if (voice == 'fake:a') signal.cancel();
    };
    await expectLater(
      renderer.render(request, cancellation: signal),
      throwsA(isA<ProcessingCancelledException>()),
    );
    expect(voices.said, [('fake:a', 'Hola, ¿qué tal?')]);

    voices
      ..said.clear()
      ..onSay = null;
    final done = await renderer.render(request);
    expect(voices.said, [('fake:b', 'Todo bien.')]);
    expect(done.starts, hasLength(2));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('una voz que no está o que nadie hace se dice antes de generar '
      'nada', () async {
    voices.missing.add('fake:b');
    await expectLater(
      renderer.render(request),
      throwsA(
        isA<SpeechAudioException>()
            .having(
              (e) => e.failure,
              'failure',
              SpeechAudioFailure.voiceMissing,
            )
            .having((e) => e.voiceId, 'voiceId', 'fake:b'),
      ),
    );
    expect(voices.said, isEmpty);

    await expectLater(
      renderer.render(
        const SpeechAudioRequest(
          workKey: 'otro',
          pieces: [SpeechAudioPiece(text: 'x', voiceId: 'nube:z')],
        ),
      ),
      throwsA(
        isA<SpeechAudioException>().having(
          (e) => e.failure,
          'failure',
          SpeechAudioFailure.voiceMissing,
        ),
      ),
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('un tramo ya hecho no necesita que su voz siga estando', () async {
    await renderer.render(request);
    voices
      ..said.clear()
      ..missing.add('fake:a');
    final done = await renderer.render(request);
    expect(done.starts, hasLength(2));
    expect(voices.said, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('un motor que falla deja la falla con su voz, y ningún archivo a '
      'medias', () async {
    voices.failOn = 'fake:b';
    await expectLater(
      renderer.render(request),
      throwsA(
        isA<SpeechAudioException>()
            .having((e) => e.failure, 'failure', SpeechAudioFailure.engine)
            .having((e) => e.voiceId, 'voiceId', 'fake:b'),
      ),
    );
    final left = Directory(
      p.join(root.path, 'podcast-c1'),
    ).listSync().map((f) => p.basename(f.path));
    expect(left.where((n) => n.endsWith('.part')), isEmpty);
    // El de la voz que anduvo quedó.
    expect(left.where((n) => n.endsWith('.wav')), hasLength(1));

    // Un motor que no dejó nada también es una falla.
    voices
      ..failOn = null
      ..silentOn = 'fake:b';
    await expectLater(
      renderer.render(request),
      throwsA(
        isA<SpeechAudioException>().having(
          (e) => e.failure,
          'failure',
          SpeechAudioFailure.engine,
        ),
      ),
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('un error suelto de un motor también es una falla del motor', () async {
    voices.throwRaw = true;
    await expectLater(
      renderer.render(request),
      throwsA(
        isA<SpeechAudioException>()
            .having((e) => e.failure, 'failure', SpeechAudioFailure.engine)
            .having((e) => e.voiceId, 'voiceId', 'fake:a'),
      ),
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('si comprimir falla, es una falla del archivo', () async {
    encoder.fail = true;
    await expectLater(
      renderer.render(request),
      throwsA(
        isA<SpeechAudioException>().having(
          (e) => e.failure,
          'failure',
          SpeechAudioFailure.file,
        ),
      ),
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('discard borra la carpeta del trabajo; las abandonadas se barren '
      'solas pasadas dos semanas, nunca la del trabajo de ahora', () async {
    final old = Directory(p.join(root.path, 'podcast-viejo'))..createSync();
    const one = SpeechAudioRequest(
      workKey: 'doc-1',
      pieces: [SpeechAudioPiece(text: 'x', voiceId: 'fake:a')],
    );
    // A los trece días, todavía no.
    now = DateTime.now().add(const Duration(days: 13));
    await renderer.render(one);
    expect(old.existsSync(), isTrue);

    // A los quince, sí; la del trabajo que se retoma, no, aunque sea vieja.
    final resumed = Directory(p.join(root.path, 'podcast-c1'))..createSync();
    now = DateTime.now().add(const Duration(days: 15));
    await renderer.render(request);
    expect(old.existsSync(), isFalse);
    expect(Directory(p.join(root.path, 'doc-1')).existsSync(), isFalse);
    expect(resumed.existsSync(), isTrue);

    await renderer.discard('podcast-c1');
    expect(resumed.existsSync(), isFalse);
    // Una clave que no es un tramo no borra nada.
    await renderer.discard('..');
    expect(root.existsSync(), isTrue);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('una clave que no es un solo tramo de carpeta no se acepta', () async {
    expect(
      () => renderer.render(
        const SpeechAudioRequest(workKey: '../afuera', pieces: pieces),
      ),
      throwsArgumentError,
    );
    expect(
      () => renderer.render(
        const SpeechAudioRequest(workKey: 'vacio', pieces: []),
      ),
      throwsArgumentError,
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('el costo: nada con voces gratis; con una de la nube, lo que cobra '
      'por lo que dice (el enganche del paso 4)', () {
    expect(renderer.costOf(pieces), isNull);
    voices.prices['fake:b'] = const SpeechAudioPrice(
      per1000Characters: 0.3,
      currency: 'USD',
    );
    final cost = renderer.costOf(pieces)!;
    expect(cost.currency, 'USD');
    expect(cost.characters, 'Todo bien.'.length);
    expect(cost.amount, closeTo(0.003, 1e-9));
    // Voz por voz, para una puerta que aprueba cada una (paso 4).
    expect(cost.charactersByVoice, {'fake:b': 'Todo bien.'.length});
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('un tramo en otro formato —el MP3 de una voz de la nube, paso 4— se '
      'decodifica antes de armar, y queda como los demás', () async {
    voices.mp3.add('fake:b');
    final done = await renderer.render(request);
    expect(decoder.calls, hasLength(1));
    expect(done.starts, [
      Duration.zero,
      const Duration(milliseconds: 480 + 550),
    ]);
    // El tono decodificado no tiene silencio en los bordes: 400 ms.
    expect(done.duration, const Duration(milliseconds: 480 + 550 + 400));
    // Retomar no lo vuelve a decodificar: quedó como WAV.
    decoder.calls.clear();
    await renderer.render(request);
    expect(decoder.calls, isEmpty);
    // Un WAV de un motor no pasa nunca por el decodificador.
    voices.mp3.clear();
    await renderer.render(
      const SpeechAudioRequest(
        workKey: 'otro',
        pieces: [SpeechAudioPiece(text: 'y', voiceId: 'fake:a')],
      ),
    );
    expect(decoder.calls, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('sin con qué decodificarlo, o si el sistema falla, es una falla del '
      'archivo con su voz, y no queda nada a medias', () async {
    voices.mp3.add('fake:b');
    for (final setUp in [
      () => decoder.supported = false,
      () => decoder
        ..supported = true
        ..fail = true,
    ]) {
      setUp();
      await expectLater(
        renderer.render(request),
        throwsA(
          isA<SpeechAudioException>()
              .having((e) => e.failure, 'failure', SpeechAudioFailure.file)
              .having((e) => e.voiceId, 'voiceId', 'fake:b'),
        ),
      );
      final left = Directory(
        p.join(root.path, 'podcast-c1'),
      ).listSync().map((f) => p.basename(f.path));
      expect(left.where((n) => n.contains('.part')), isEmpty);
    }
    // Sin decodificador, tampoco.
    final bare = SpeechAudioRenderer(
      voices: () => [voices],
      workRoot: () async => root,
      encoder: encoder,
      assemble: (job) async => assembleSpeechWav(job),
    );
    await expectLater(
      bare.render(request),
      throwsA(
        isA<SpeechAudioException>().having(
          (e) => e.failure,
          'failure',
          SpeechAudioFailure.file,
        ),
      ),
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('isReady pregunta a quien hace la voz', () async {
    expect(await renderer.isReady('fake:a'), isTrue);
    voices.missing.add('fake:a');
    expect(await renderer.isReady('fake:a'), isFalse);
    expect(await renderer.isReady('nube:x'), isFalse);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test(
    'el codificador de la plataforma: fuera de Android no comprime',
    () async {
      expect(
        await const PlatformSpeechAudioEncoder(android: false).toM4a('a', 'b'),
        isFalse,
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('hasWork: hay algo hecho de un intento cortado, y nada sin empezar, '
      'después de soltarlo ni con una clave que no es una carpeta (F47, '
      'paso 5)', () async {
    expect(await renderer.hasWork('podcast-c1'), isFalse);
    final signal = CancellationSignal();
    voices.onSay = (voice, _) {
      if (voice == 'fake:a') signal.cancel();
    };
    await expectLater(
      renderer.render(request, cancellation: signal),
      throwsA(isA<ProcessingCancelledException>()),
    );
    expect(await renderer.hasWork('podcast-c1'), isTrue);
    expect(await renderer.hasWork('otro'), isFalse);
    expect(await renderer.hasWork('../podcast-c1'), isFalse);
    // Una carpeta con solo un tramo a medias no es lo hecho.
    Directory(p.join(root.path, 'medias')).createSync();
    File(p.join(root.path, 'medias', 't-x.wav.part')).writeAsBytesSync([1]);
    expect(await renderer.hasWork('medias'), isFalse);
    await renderer.discard('podcast-c1');
    expect(await renderer.hasWork('podcast-c1'), isFalse);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
