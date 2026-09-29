import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:sinapsis/core/error/exceptions.dart';
import 'package:sinapsis/features/transform/domain/clients/youtube_client.dart';
// Con prefijo: el paquete trae su propia `VideoUnavailableException`, que
// colisiona con la del dominio. El prefijo desambigua y, de paso, deja a la
// vista qué tipos vienen de afuera y cuáles son nuestros.
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_api;

/// [YouTubeClient] sobre `youtube_explode_dart`.
///
/// El paquete no usa la API oficial de YouTube, y esa es justamente la razón
/// de elegirlo: no hace falta clave, no hay cuotas diarias y no hay una
/// consola de Google donde registrar el proyecto. Es lo que hace DownSub por
/// dentro, sin depender de que DownSub siga existiendo.
///
/// **Todo pedido lleva su límite de tiempo** (F21). El paquete habla con
/// YouTube por su propio cliente HTTP, sin ninguno: una conexión que moría a
/// mitad de camino —el teléfono se durmió, pasó de wifi a datos— dejaba la
/// espera colgada para siempre, y con ella la cola entera. Un pedido que se
/// pasa de [callTimeout] lanza `TimeoutException`; una descarga que deja de
/// recibir datos durante [stallTimeout], también. Los cortes de red se
/// traducen a [NetworkException]: se guardan como "sin conexión", no como un
/// error desconocido.
class YoutubeExplodeClient implements YouTubeClient {
  const YoutubeExplodeClient({
    yt_api.YoutubeExplode Function()? create,
    this.callTimeout = const Duration(seconds: 45),
    this.stallTimeout = const Duration(seconds: 45),
  }) : _create = create ?? yt_api.YoutubeExplode.new;

  /// Cómo se arma el cliente del paquete. Se inyecta para poder probar los
  /// límites sin salir a la red.
  final yt_api.YoutubeExplode Function() _create;

  /// Lo más que puede tardar un pedido suelto: los datos del video, la lista
  /// de subtítulos, la pista elegida, la lista de pistas de audio. Holgado
  /// —el paquete reintenta solo los fallos pasajeros, y una conexión móvil
  /// lenta no es un cuelgue—, pero finito.
  final Duration callTimeout;

  /// Cuánto puede pasar una descarga sin recibir ni un byte antes de darla
  /// por muerta. No es un tope a la descarga entera: el audio de un video de
  /// cuatro horas tarda lo que tarda mientras siga llegando.
  final Duration stallTimeout;

  @override
  Future<YouTubeVideoData> fetchVideo(
    String videoId, {
    List<String> preferredLanguages = const ['es', 'en'],
  }) async {
    final yt = _create();

    try {
      // Las dos llamadas son independientes —una trae metadata del video,
      // la otra la pista de subtítulos— así que arrancan las dos antes de
      // esperar cualquiera de las dos: esperarlas una detrás de la otra
      // sumaría su tiempo en vez de superponerlo.
      final videoFuture = yt.videos.get(videoId).timeout(callTimeout);
      final transcriptFuture = _fetchTranscript(yt, videoId, preferredLanguages)
        ..ignore();
      // `ignore()` no descarta el resultado —se espera abajo igual—: solo
      // evita que, si el primero falla y se sale sin esperar al segundo, el
      // error del segundo quede sin atrapar.
      final video = await videoFuture;
      final transcript = await transcriptFuture;

      return YouTubeVideoData(
        title: video.title,
        authorName: video.author,
        authorChannelUrl: 'https://www.youtube.com/channel/${video.channelId}',
        publishedAt: video.publishDate ?? video.uploadDate,
        duration: video.duration,
        description: video.description,
        transcript: transcript,
      );
      // Un solo `catch` cubre los tres casos de "este video no está y no va
      // a estar": en el paquete, `VideoUnavailableException` (borrado o
      // privado) y `VideoRequiresPurchaseException` (de pago) extienden
      // `VideoUnplayableException`. Se traduce al tipo del dominio para que
      // quien llame no tenga que conocer las excepciones del paquete.
    } on yt_api.VideoUnplayableException {
      throw VideoUnavailableException(videoId);
    } on http.ClientException catch (error) {
      throw _networkFailure(error);
    } on yt_api.TransientFailureException catch (error) {
      throw _networkFailure(error);
    } on yt_api.RequestLimitExceededException catch (error) {
      throw _networkFailure(error);
    } finally {
      // Cierra el cliente HTTP interno. Sin esto, cada video procesado deja
      // una conexión abierta y una cola larga las acumula todas.
      yt.close();
    }
  }

  @override
  Future<Uint8List> fetchAudio(String videoId) async {
    final yt = _create();

    try {
      final manifest = await yt.videos.streams
          .getManifest(videoId)
          .timeout(callTimeout);
      // La de mayor bitrate entre las que traen solo audio: no hace falta
      // el video para escuchar ni para transcribir, y bajar el archivo
      // completo pesaría muchas veces más para nada que se vaya a usar.
      final audioStream = manifest.audioOnly.withHighestBitrate();

      // `BytesBuilder` y no una `List<int>`: la lista guarda cada byte en un
      // entero de 8, y el audio de un video largo se multiplicaba por ocho en
      // memoria (F21).
      final bytes = BytesBuilder(copy: false);
      await for (final chunk
          in yt.videos.streams.get(audioStream).timeout(stallTimeout)) {
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } on yt_api.VideoUnplayableException {
      throw VideoUnavailableException(videoId);
    } on http.ClientException catch (error) {
      throw _networkFailure(error);
    } on yt_api.TransientFailureException catch (error) {
      throw _networkFailure(error);
    } on yt_api.RequestLimitExceededException catch (error) {
      throw _networkFailure(error);
    } finally {
      yt.close();
    }
  }

  Future<List<TranscriptLine>> _fetchTranscript(
    yt_api.YoutubeExplode yt,
    String videoId,
    List<String> preferredLanguages,
  ) async {
    final manifest = await yt.videos.closedCaptions
        .getManifest(videoId)
        .timeout(callTimeout);
    final chosen = _pickTrack(manifest, preferredLanguages);
    if (chosen == null) return const [];

    final track = await yt.videos.closedCaptions
        .get(chosen)
        .timeout(callTimeout);

    return track.captions
        .map(
          (caption) =>
              TranscriptLine(offset: caption.offset, text: caption.text.trim()),
        )
        .where((line) => line.text.isNotEmpty)
        .toList();
  }

  /// Elige qué pista bajar.
  ///
  /// El orden de preferencia responde a qué sirve más:
  ///
  /// 1. Un idioma preferido, con subtítulos hechos por una persona.
  /// 2. Ese mismo idioma, autogenerados — peores, pero utilizables.
  /// 3. Cualquier pista que haya. Una transcripción en otro idioma sigue
  ///    siendo mejor que ninguna: se puede leer, buscar y traducir después.
  yt_api.ClosedCaptionTrackInfo? _pickTrack(
    yt_api.ClosedCaptionManifest manifest,
    List<String> preferredLanguages,
  ) {
    if (manifest.tracks.isEmpty) return null;

    for (final language in preferredLanguages) {
      final inLanguage = manifest.tracks.where(
        (track) => track.language.code.toLowerCase().startsWith(language),
      );
      if (inLanguage.isEmpty) continue;

      final human = inLanguage.where((track) => !track.isAutoGenerated);
      return human.isNotEmpty ? human.first : inLanguage.first;
    }

    final human = manifest.tracks.where((track) => !track.isAutoGenerated);
    return human.isNotEmpty ? human.first : manifest.tracks.first;
  }
}

/// Un corte de red —del cliente HTTP, o un fallo pasajero que el paquete ya
/// no pudo reintentar— como [NetworkException]: se guarda como "sin
/// conexión", que se resuelve reintentando, y no como un error desconocido.
NetworkException _networkFailure(Object error) =>
    NetworkException(message: 'YouTube no respondió: $error');
