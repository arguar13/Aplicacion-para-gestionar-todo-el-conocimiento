import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/error/exceptions.dart';
import 'package:sinapsis/features/transform/data/clients/youtube_clients.dart';
import 'package:sinapsis/features/transform/data/clients/youtube_explode_client.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_api;

class _MockYoutube extends Mock implements yt_api.YoutubeExplode {}

class _MockVideos extends Mock implements yt_api.VideoClient {}

class _MockCaptions extends Mock implements yt_api.ClosedCaptionClient {}

class _MockStreams extends Mock implements yt_api.StreamClient {}

class _MockManifest extends Mock implements yt_api.StreamManifest {}

class _MockAudio extends Mock implements yt_api.AudioOnlyStreamInfo {}

/// El cliente contra un YouTube falso: lo que se prueba acá son los límites
/// de tiempo y la traducción de los cortes de red (F21), no el paquete.
/// Una pista de audio de verdad, armada como la arma el paquete —desde
/// JSON—: la clase de la pista doblada (`AudioTrack`) no es pública.
yt_api.AudioOnlyStreamInfo _track(
  int bitsPerSecond, {
  String? language,
  bool isDefault = false,
  int totalBytes = 1000,
}) => yt_api.AudioOnlyStreamInfo.fromJson({
  'videoId': {'value': 'dQw4w9WgXcQ'},
  'tag': 140,
  'url': 'https://example.com/$language-$bitsPerSecond',
  'container': {'name': 'mp4'},
  'size': {'totalBytes': totalBytes},
  'bitrate': {'bitsPerSecond': bitsPerSecond},
  'audioCodec': 'mp4a.40.2',
  'qualityLabel': 'medium',
  'fragments': const <Object>[],
  'codec': 'audio/mp4',
  'audioTrack': language == null
      ? null
      : {
          'displayName': language,
          'id': '$language.4',
          'audioIsDefault': isDefault,
        },
});

void main() {
  late _MockYoutube youtube;
  late _MockVideos videos;
  late _MockCaptions captions;
  late _MockStreams streams;

  setUp(() {
    youtube = _MockYoutube();
    videos = _MockVideos();
    captions = _MockCaptions();
    streams = _MockStreams();
    when(() => youtube.videos).thenReturn(videos);
    when(() => youtube.close()).thenReturn(null);
    when(() => videos.closedCaptions).thenReturn(captions);
    when(() => videos.streams).thenReturn(streams);
  });

  YoutubeExplodeClient client() => YoutubeExplodeClient(
    create: () => youtube,
    callTimeout: const Duration(milliseconds: 50),
    stallTimeout: const Duration(milliseconds: 50),
  );

  group('un pedido que nunca responde vence, no cuelga la cola', () {
    test('los datos del video', () async {
      // El short de YouTube de 2 minutos (F21): una conexión muerta dejaba la
      // espera colgada para siempre.
      when(
        () => videos.get(any<dynamic>()),
      ).thenAnswer((_) => Completer<yt_api.Video>().future);
      when(
        () => captions.getManifest(any<dynamic>()),
      ).thenAnswer((_) => Completer<yt_api.ClosedCaptionManifest>().future);

      await expectLater(
        client().fetchVideo('abc'),
        throwsA(isA<TimeoutException>()),
      );
      verify(() => youtube.close()).called(1);
    });

    test('la lista de pistas de audio, después de reintentarla', () async {
      var calls = 0;
      when(
        () => streams.getManifest(
          any<dynamic>(),
          ytClients: any(named: 'ytClients'),
        ),
      ).thenAnswer((_) {
        calls++;
        return Completer<yt_api.StreamManifest>().future;
      });

      await expectLater(
        YoutubeExplodeClient(
          create: () => youtube,
          callTimeout: const Duration(milliseconds: 50),
          resumeBackoff: const Duration(milliseconds: 1),
        ).openAudio('abc'),
        throwsA(isA<TimeoutException>()),
      );
      expect(calls, 3);
    });
  });

  test('un corte de red llega como "sin conexión", no como un error '
      'desconocido', () async {
    when(
      () => videos.get(any<dynamic>()),
    ).thenAnswer((_) async => throw http.ClientException('socket cerrado'));
    when(
      () => captions.getManifest(any<dynamic>()),
    ).thenAnswer((_) async => throw http.ClientException('socket cerrado'));

    await expectLater(
      client().fetchVideo('abc'),
      throwsA(isA<NetworkException>()),
    );
  });

  group('bajar el audio retoma desde donde quedó (F24)', () {
    late _MockAudio audio;
    // Cada intento: desde qué byte se pidió.
    late List<int> requestedFrom;

    setUp(() {
      audio = _MockAudio();
      when(() => audio.size).thenReturn(const yt_api.FileSize(10));
      when(() => audio.tag).thenReturn(251);
      when(() => audio.audioTrack).thenReturn(null);
      when(() => audio.bitrate).thenReturn(const yt_api.Bitrate(160000));
      when(() => audio.container).thenReturn(yt_api.StreamContainer.webM);
      final manifest = _MockManifest();
      when(() => manifest.audioOnly).thenReturn(UnmodifiableListView([audio]));
      when(
        () => streams.getManifest(
          any<dynamic>(),
          ytClients: any(named: 'ytClients'),
        ),
      ).thenAnswer((_) async => manifest);
      requestedFrom = [];
    });

    /// Un cliente cuyo YouTube responde cada pedido con [attempts], en
    /// orden: los bytes que manda y si después se traba (no manda más).
    YoutubeExplodeClient resuming(List<(List<int>, bool)> attempts) {
      var call = 0;
      return YoutubeExplodeClient(
        create: () => youtube,
        stallTimeout: const Duration(milliseconds: 40),
        resumeBackoff: const Duration(milliseconds: 1),
        maxResumeAttempts: 3,
        fetchRange: (_, _, start) async* {
          requestedFrom.add(start);
          final (bytes, stalls) =
              attempts[call < attempts.length ? call : attempts.length - 1];
          call++;
          if (bytes.isNotEmpty) yield bytes;
          if (stalls) await Completer<void>().future;
        },
      );
    }

    Future<List<int>> drain(YoutubeExplodeClient client) async {
      final opened = await client.openAudio('abc');
      return [for (final chunk in await opened.bytes.toList()) ...chunk];
    }

    test('una conexión que se traba a mitad de camino se retoma desde el '
        'byte siguiente, sin perder ni repetir nada', () async {
      final bytes = await drain(
        resuming([
          ([0, 1, 2, 3], true),
          ([4, 5, 6], true),
          ([7, 8, 9], false),
        ]),
      );

      expect(bytes, List.generate(10, (i) => i));
      expect(requestedFrom, [0, 4, 7]);
      verify(() => youtube.close()).called(1);
    });

    test('mientras avance no se rinde nunca, aunque se trabe más veces que '
        'el máximo de intentos', () async {
      final bytes = await drain(
        resuming([
          for (var i = 0; i < 10; i++) ([i], i < 9),
        ]),
      );

      expect(bytes, List.generate(10, (i) => i));
    });

    test('si deja de avanzar del todo, se rinde con "tardó demasiado" '
        'después de los intentos, no antes', () async {
      await expectLater(
        drain(
          resuming([
            ([0, 1], true),
            (const <int>[], true),
          ]),
        ),
        throwsA(isA<TimeoutException>()),
      );
      // El primero, y 4 más sin avance: el último que se rinde.
      expect(requestedFrom, [0, 2, 2, 2, 2]);
    });

    test('la lista de pistas que tarda la primera vez se pide de nuevo, '
        'y la bajada sigue', () async {
      final manifest = _MockManifest();
      when(() => manifest.audioOnly).thenReturn(UnmodifiableListView([audio]));
      var calls = 0;
      when(
        () => streams.getManifest(
          any<dynamic>(),
          ytClients: any(named: 'ytClients'),
        ),
      ).thenAnswer((_) {
        if (calls++ == 0) return Completer<yt_api.StreamManifest>().future;
        return Future.value(manifest);
      });

      final bytes = await drain(
        YoutubeExplodeClient(
          create: () => youtube,
          callTimeout: const Duration(milliseconds: 50),
          resumeBackoff: const Duration(milliseconds: 1),
          fetchRange: (_, _, start) async* {
            yield List.generate(10, (i) => i);
          },
        ),
      );

      expect(bytes, hasLength(10));
    });

    test('mientras quien lee está en pausa —el disco escribiendo— no cuenta '
        'como traba', () async {
      final source = StreamController<List<int>>();
      final guarded = stallGuarded(
        source.stream,
        const Duration(milliseconds: 40),
      );
      final received = <int>[];
      final subscription = guarded.listen(received.addAll)..pause();
      source.add([1]);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      subscription.resume();
      source.add([2]);
      await source.close();
      await Future<void>.delayed(Duration.zero);

      expect(received, [1, 2]);
      await subscription.cancel();
    });

    test(
      'un 403 una vez —la dirección venció a mitad de un video de '
      'horas— se resuelve pidiendo una nueva y siguiendo desde ahí',
      () async {
        var call = 0;
        final client = YoutubeExplodeClient(
          create: () => youtube,
          resumeBackoff: const Duration(milliseconds: 1),
          fetchRange: (_, _, start) async* {
            requestedFrom.add(start);
            if (call++ == 0) {
              yield [0, 1, 2, 3, 4, 5];
              throw const DownloadBlockedException(message: '403');
            }
            yield [6, 7, 8, 9];
          },
        );

        expect(await drain(client), List.generate(10, (i) => i));
        expect(requestedFrom, [0, 6]);
        // Se pidió la lista de nuevo: la de abrir, y la de la dirección nueva.
        verify(
          () => streams.getManifest(
            any<dynamic>(),
            ytClients: any(named: 'ytClients'),
          ),
        ).called(2);
      },
    );

    test('al pedir una dirección nueva sigue con la misma pista: con audio '
        'doblado, el mismo formato en otro idioma no sirve', () async {
      // El original y un doblaje con el mismo formato: antes la dirección
      // nueva se buscaba solo por el formato, y la bajada podía seguir en
      // otro idioma a mitad de camino.
      final dubbed = _track(160000, language: 'en', totalBytes: 10);
      final original = _track(
        128000,
        language: 'es',
        isDefault: true,
        totalBytes: 10,
      );
      final manifest = _MockManifest();
      when(
        () => manifest.audioOnly,
      ).thenReturn(UnmodifiableListView([dubbed, original]));
      when(
        () => streams.getManifest(
          any<dynamic>(),
          ytClients: any(named: 'ytClients'),
        ),
      ).thenAnswer((_) async => manifest);
      final fetched = <Uri>[];
      var call = 0;
      final client = YoutubeExplodeClient(
        create: () => youtube,
        resumeBackoff: const Duration(milliseconds: 1),
        fetchRange: (_, audio, start) async* {
          fetched.add(audio.url);
          if (call++ == 0) {
            yield [0, 1, 2, 3, 4, 5];
            throw const DownloadBlockedException(message: '403');
          }
          yield [6, 7, 8, 9];
        },
      );

      expect(await drain(client), List.generate(10, (i) => i));
      expect(fetched, [original.url, original.url]);
    });

    test('un 403 que sigue desde el mismo byte es un bloqueo: se informa en '
        'el acto, sin agotar los intentos', () async {
      final client = YoutubeExplodeClient(
        create: () => youtube,
        resumeBackoff: const Duration(seconds: 30),
        fetchRange: (_, _, start) async* {
          requestedFrom.add(start);
          if (start == 0) yield [0, 1];
          throw const DownloadBlockedException(message: '403');
        },
      );

      await expectLater(
        drain(client),
        throwsA(isA<DownloadBlockedException>()),
      );
      expect(requestedFrom, [0, 2]);
    });

    test('las pistas se piden primero por la vía de visionOS —la que hoy '
        'deja bajarlas enteras—, y si el video no está por ahí, por las del '
        'paquete', () async {
      final manifest = _MockManifest();
      when(() => manifest.audioOnly).thenReturn(UnmodifiableListView([audio]));
      final asked = <List<yt_api.YoutubeApiClient>?>[];
      when(
        () => streams.getManifest(
          any<dynamic>(),
          ytClients: any(named: 'ytClients'),
        ),
      ).thenAnswer((invocation) async {
        final clients =
            invocation.namedArguments[#ytClients]
                as List<yt_api.YoutubeApiClient>?;
        asked.add(clients);
        if (clients != null) {
          throw yt_api.VideoUnplayableException('hecho para chicos');
        }
        return manifest;
      });

      final bytes = await drain(
        YoutubeExplodeClient(
          create: () => youtube,
          fetchRange: (_, _, _) async* {
            yield List.generate(10, (i) => i);
          },
        ),
      );

      expect(bytes, hasLength(10));
      expect(asked, [
        [youTubeVisionOsClient],
        null,
      ]);
    });

    test('un corte de red también se retoma', () async {
      var call = 0;
      final client = YoutubeExplodeClient(
        create: () => youtube,
        resumeBackoff: const Duration(milliseconds: 1),
        fetchRange: (_, _, start) async* {
          requestedFrom.add(start);
          if (call++ == 0) {
            yield [0, 1, 2, 3, 4];
            throw http.ClientException('socket cerrado');
          }
          yield [5, 6, 7, 8, 9];
        },
      );

      expect(await drain(client), List.generate(10, (i) => i));
      expect(requestedFrom, [0, 5]);
    });
  });

  group('qué subtítulos se bajan (F22)', () {
    ({String language, bool autoGenerated}) human(String language) =>
        (language: language, autoGenerated: false);
    ({String language, bool autoGenerated}) auto(String language) =>
        (language: language, autoGenerated: true);

    test('los del idioma que se habla, no una traducción al español', () {
      // Hablado en inglés —la automática es en inglés— con subtítulos en
      // español subidos por el autor: antes se guardaba la traducción.
      expect(pickCaptionTrack([human('es'), auto('en'), human('en')], []), 2);
    });

    test('sin subtítulos hechos por una persona en ese idioma, la '
        'automática del idioma hablado', () {
      expect(pickCaptionTrack([human('es'), auto('en')], []), 1);
    });

    test('en el idioma hablado, la hecha por una persona antes que la '
        'automática, aunque venga con región', () {
      expect(pickCaptionTrack([auto('es'), human('es-419')], []), 1);
    });

    test('un idioma elegido por el usuario pasa adelante', () {
      expect(pickCaptionTrack([auto('en'), human('pt-BR')], ['pt']), 1);
    });

    test('sin automática no se sabe qué se habla: español, inglés, la '
        'primera', () {
      expect(pickCaptionTrack([human('fr'), human('en')], []), 1);
      expect(pickCaptionTrack([human('fr'), human('de')], []), 0);
    });

    test('sin ninguna pista, ninguna', () {
      expect(pickCaptionTrack([], []), isNull);
    });

    test('el idioma principal de un código con región', () {
      expect(primaryLanguage('es-419'), 'es');
      expect(primaryLanguage('pt_BR'), 'pt');
      expect(primaryLanguage('EN'), 'en');
    });
  });

  group('qué pista de audio se baja: la original, no un doblaje', () {
    yt_api.AudioOnlyStreamInfo track(
      int bitsPerSecond, {
      String? language,
      bool isDefault = false,
    }) => _track(bitsPerSecond, language: language, isDefault: isDefault);

    test('el original gana aunque un doblaje traiga más calidad', () {
      final original = track(128000, language: 'es', isDefault: true);
      final dubbed = [
        track(160000, language: 'en'),
        track(160000, language: 'ar'),
      ];

      expect(originalAudioOf([...dubbed, original]), same(original));
    });

    test('entre las del original, la de mayor calidad', () {
      final low = track(50000, language: 'es', isDefault: true);
      final high = track(160000, language: 'es', isDefault: true);

      expect(
        originalAudioOf([low, track(256000, language: 'pt'), high]),
        same(high),
      );
    });

    test('un video sin doblajes: la de mayor calidad', () {
      final low = track(50000);
      final high = track(160000);

      expect(originalAudioOf([low, high]), same(high));
    });

    test('si ninguna está marcada como la de siempre, entre todas', () {
      final best = track(160000, language: 'en');

      expect(originalAudioOf([track(50000, language: 'es'), best]), same(best));
    });

    test('sin pistas no hay qué elegir', () {
      expect(() => originalAudioOf(const []), throwsStateError);
    });
  });
}
