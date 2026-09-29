import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/error/exceptions.dart';
import 'package:sinapsis/features/transform/data/clients/youtube_explode_client.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_api;

class _MockYoutube extends Mock implements yt_api.YoutubeExplode {}

class _MockVideos extends Mock implements yt_api.VideoClient {}

class _MockCaptions extends Mock implements yt_api.ClosedCaptionClient {}

class _MockStreams extends Mock implements yt_api.StreamClient {}

/// El cliente contra un YouTube falso: lo que se prueba acá son los límites
/// de tiempo y la traducción de los cortes de red (F21), no el paquete.
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

    test('la lista de pistas de audio', () async {
      when(
        () => streams.getManifest(any<dynamic>()),
      ).thenAnswer((_) => Completer<yt_api.StreamManifest>().future);

      await expectLater(
        client().openAudio('abc'),
        throwsA(isA<TimeoutException>()),
      );
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
}
