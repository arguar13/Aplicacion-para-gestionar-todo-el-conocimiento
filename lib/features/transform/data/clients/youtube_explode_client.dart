import 'dart:async';

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
    List<String> preferredLanguages = const [],
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
      final (transcript, transcriptLanguage) = await transcriptFuture;

      return YouTubeVideoData(
        title: video.title,
        authorName: video.author,
        authorChannelUrl: 'https://www.youtube.com/channel/${video.channelId}',
        publishedAt: video.publishDate ?? video.uploadDate,
        duration: video.duration,
        description: video.description,
        transcript: transcript,
        transcriptLanguage: transcriptLanguage,
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
  Future<YouTubeAudioStream> openAudio(String videoId) async {
    final yt = _create();

    final yt_api.AudioOnlyStreamInfo audio;
    try {
      final manifest = await yt.videos.streams
          .getManifest(videoId)
          .timeout(callTimeout);
      // La de mayor bitrate entre las que traen solo audio: no hace falta
      // el video para escuchar, y bajar el archivo completo pesaría muchas
      // veces más para nada que se vaya a usar.
      audio = manifest.audioOnly.withHighestBitrate();
    } on Object catch (error) {
      // Nada que devolver: el cliente se cierra acá, no al terminar el
      // stream que nunca llega a existir.
      yt.close();
      if (error is yt_api.VideoUnplayableException) {
        throw VideoUnavailableException(videoId);
      }
      if (_isNetworkFailure(error)) throw _networkFailure(error);
      rethrow;
    }

    return YouTubeAudioStream(
      bytes: _audioBytes(yt, audio),
      totalBytes: audio.size.totalBytes,
      // Un audio solo en un contenedor MP4 es un M4A: el nombre que
      // reconocen los reproductores.
      fileExtension: audio.container == yt_api.StreamContainer.mp4
          ? 'm4a'
          : audio.container.name,
    );
  }

  /// El audio por partes, tal como llega. Se corta si deja de llegar
  /// durante [stallTimeout] —no por su duración total: el de cuatro horas
  /// tarda lo que tarda mientras siga llegando—, y cierra el cliente al
  /// terminar, al fallar o si quien lo lee lo abandona.
  Stream<List<int>> _audioBytes(
    yt_api.YoutubeExplode yt,
    yt_api.AudioOnlyStreamInfo audio,
  ) async* {
    try {
      yield* yt.videos.streams.get(audio).timeout(stallTimeout);
    } on Object catch (error) {
      if (_isNetworkFailure(error)) throw _networkFailure(error);
      rethrow;
    } finally {
      yt.close();
    }
  }

  Future<(List<TranscriptLine>, String?)> _fetchTranscript(
    yt_api.YoutubeExplode yt,
    String videoId,
    List<String> preferredLanguages,
  ) async {
    final manifest = await yt.videos.closedCaptions
        .getManifest(videoId)
        .timeout(callTimeout);
    final index = pickCaptionTrack([
      for (final track in manifest.tracks)
        (language: track.language.code, autoGenerated: track.isAutoGenerated),
    ], preferredLanguages);
    if (index == null) return (const <TranscriptLine>[], null);
    final chosen = manifest.tracks[index];

    final track = await yt.videos.closedCaptions
        .get(chosen)
        .timeout(callTimeout);

    final lines = track.captions
        .map(
          (caption) =>
              TranscriptLine(offset: caption.offset, text: caption.text.trim()),
        )
        .where((line) => line.text.isNotEmpty)
        .toList();
    return (lines, primaryLanguage(chosen.language.code));
  }
}

/// Un corte de red —del cliente HTTP, o un fallo pasajero que el paquete ya
/// no pudo reintentar— como [NetworkException]: se guarda como "sin
/// conexión", que se resuelve reintentando, y no como un error desconocido.
NetworkException _networkFailure(Object error) =>
    NetworkException(message: 'YouTube no respondió: $error');

bool _isNetworkFailure(Object error) =>
    error is http.ClientException ||
    error is yt_api.TransientFailureException ||
    error is yt_api.RequestLimitExceededException;

/// Qué pista de subtítulos bajar, de [tracks] —su idioma y si es
/// automática—: su posición, o `null` si no hay ninguna (F22).
///
/// Lo que manda es la fidelidad a lo que se DICE en el video. YouTube
/// genera la pista automática sobre el audio original, así que su idioma es
/// el que se habla. En orden:
///
/// 1. Un idioma que eligió el usuario ([preferred]): hecha por una persona,
///    o si no automática.
/// 2. El idioma que se habla: hecha por una persona —lo más fiel que
///    hay—, o si no la automática.
/// 3. Sin pista automática no se sabe qué se habla: español, después
///    inglés, después la primera que haya —hecha por una persona antes que
///    automática—. Más vale una transcripción en otro idioma que ninguna.
///
/// Antes se prefería el español en cualquier caso: un video hablado en
/// inglés con subtítulos en español subidos por su autor guardaba la
/// traducción, no lo que se dijo.
int? pickCaptionTrack(
  List<({String language, bool autoGenerated})> tracks,
  List<String> preferred,
) {
  if (tracks.isEmpty) return null;

  int? best(String language) {
    int? auto;
    for (var i = 0; i < tracks.length; i++) {
      if (primaryLanguage(tracks[i].language) != language) continue;
      if (!tracks[i].autoGenerated) return i;
      auto ??= i;
    }
    return auto;
  }

  for (final language in preferred) {
    if (best(primaryLanguage(language)) case final index?) return index;
  }

  final spoken = tracks.where((track) => track.autoGenerated).firstOrNull;
  if (spoken != null) return best(primaryLanguage(spoken.language));

  for (final language in const ['es', 'en']) {
    if (best(language) case final index?) return index;
  }
  final human = tracks.indexWhere((track) => !track.autoGenerated);
  return human >= 0 ? human : 0;
}

/// El idioma principal de un código: "es-419" y "es_AR" son "es".
String primaryLanguage(String code) =>
    code.toLowerCase().split(RegExp('[-_]')).first;
