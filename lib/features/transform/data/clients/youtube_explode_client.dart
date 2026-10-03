import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:sinapsis/core/error/exceptions.dart';
import 'package:sinapsis/features/transform/data/clients/youtube_clients.dart';
import 'package:sinapsis/features/transform/domain/clients/youtube_client.dart';
// Con prefijo: el paquete trae su propia `VideoUnavailableException`, que
// colisiona con la del dominio. El prefijo desambigua y, de paso, deja a la
// vista qué tipos vienen de afuera y cuáles son nuestros.
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_api;

/// De dónde se baja una parte de una pista: los bytes desde [start] hasta
/// el final. Se inyecta para poder probar el retomar sin salir a la red.
typedef AudioRangeFetcher =
    Stream<List<int>> Function(
      yt_api.YoutubeExplode yt,
      yt_api.AudioOnlyStreamInfo audio,
      int start,
    );

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
    AudioRangeFetcher? fetchRange,
    this.callTimeout = const Duration(seconds: 45),
    this.stallTimeout = const Duration(seconds: 45),
    this.maxResumeAttempts = 8,
    this.resumeBackoff = const Duration(seconds: 2),
  }) : _create = create ?? yt_api.YoutubeExplode.new,
       _fetchRange = fetchRange ?? _fetchRangeFromYouTube;

  /// Cómo se arma el cliente del paquete. Se inyecta para poder probar los
  /// límites sin salir a la red.
  final yt_api.YoutubeExplode Function() _create;

  /// Cómo se pide una parte de una pista: ver [AudioRangeFetcher].
  final AudioRangeFetcher _fetchRange;

  /// Cuántas veces seguidas se retoma una bajada que se trabó o se cortó
  /// **sin haber avanzado ni un byte** antes de darla por perdida. Cada vez
  /// que llega algo, la cuenta vuelve a cero: un audio de horas en una red
  /// que se traba de a ratos llega entero.
  final int maxResumeAttempts;

  /// La espera antes del primer retomar; se duplica en cada intento seguido
  /// sin avance, hasta medio minuto.
  final Duration resumeBackoff;

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
      final manifest = await _manifestWithRetries(yt, videoId);
      // La original de mayor bitrate entre las que traen solo audio: no
      // hace falta el video para escuchar, y bajar el archivo completo
      // pesaría muchas veces más para nada que se vaya a usar. Ver
      // [originalAudioOf].
      audio = originalAudioOf(manifest.audioOnly);
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
      bytes: _audioBytes(yt, videoId, audio),
      totalBytes: audio.size.totalBytes,
      // Un audio solo en un contenedor MP4 es un M4A: el nombre que
      // reconocen los reproductores.
      fileExtension: audio.container == yt_api.StreamContainer.mp4
          ? 'm4a'
          : audio.container.name,
    );
  }

  /// La lista de pistas de [videoId], reintentando si tarda de más o se
  /// corta: es lo primero que se pide antes de bajar el audio, y en una red
  /// lenta un solo intento con su tope fallaba aunque el siguiente hubiera
  /// andado (F24). Lo que no es una traba ni un corte —un video que no
  /// existe— no se reintenta.
  Future<yt_api.StreamManifest> _manifestWithRetries(
    yt_api.YoutubeExplode yt,
    String videoId,
  ) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await _manifest(yt, videoId);
      } on Object catch (error) {
        if (!_isResumable(error) || attempt >= _manifestAttempts) rethrow;
        await Future<void>.delayed(_backoff(attempt));
      }
    }
  }

  /// La lista de pistas por la vía de visionOS —la única que hoy deja bajar
  /// las pistas enteras: ver [youTubeVisionOsClient]—, y por las del paquete
  /// si por ahí el video no está (los "hechos para chicos"). Una traba o un
  /// corte no cambian de vía: los reintenta quien llama.
  Future<yt_api.StreamManifest> _manifest(
    yt_api.YoutubeExplode yt,
    String videoId,
  ) async {
    try {
      final manifest = await yt.videos.streams
          .getManifest(videoId, ytClients: [youTubeVisionOsClient])
          .timeout(callTimeout);
      if (manifest.audioOnly.isNotEmpty) return manifest;
    } on Object catch (error) {
      if (_isResumable(error)) rethrow;
    }
    return yt.videos.streams.getManifest(videoId).timeout(callTimeout);
  }

  /// Cuántas veces se pide la lista de pistas antes de rendirse.
  static const _manifestAttempts = 3;

  /// El audio por partes, tal como llega, **retomando desde el byte donde
  /// quedó** cada vez que la conexión se traba o se corta (F24).
  ///
  /// El paquete, ante una conexión que queda abierta sin mandar nada, espera
  /// para siempre —se traga los errores del cuerpo de la respuesta—: así,
  /// pasado [stallTimeout] sin datos, se cerraba la descarga entera y se
  /// tiraba todo lo bajado. En una red que se traba de a ratos —datos
  /// móviles, ciertos wifi— un short de dos minutos fallaba siempre con
  /// "tardó demasiado", y un video de horas no tenía chance. Ahora cada
  /// traba o corte cierra esa conexión y abre otra pidiendo desde el byte
  /// siguiente, con una espera creciente entre intento e intento; las
  /// direcciones de YouTube vencen a las pocas horas, así que al retomar se
  /// pide la lista de pistas de nuevo. Se rinde solo después de
  /// [maxResumeAttempts] intentos seguidos sin avanzar nada.
  ///
  /// Cierra el cliente al terminar, al fallar o si quien lo lee lo
  /// abandona.
  Stream<List<int>> _audioBytes(
    yt_api.YoutubeExplode yt,
    String videoId,
    yt_api.AudioOnlyStreamInfo audio,
  ) async* {
    final total = audio.size.totalBytes;
    var current = audio;
    var received = 0;
    var failures = 0;
    // Dónde se pidió una dirección nueva por un 403: si el siguiente pedido
    // desde ahí vuelve a dar 403, no venció, está bloqueado.
    int? renewedAt;
    try {
      while (total <= 0 || received < total) {
        final before = received;
        Object? stopped;
        // Un iterador y no `await for`: al salir de un `await for` se espera
        // a que la conexión trabada termine de cerrarse —y una trabada no
        // termina nunca—. Acá se la suelta sin esperarla: el pedido nuevo
        // no depende de que el viejo se entere.
        final parts = StreamIterator(
          stallGuarded(_fetchRange(yt, current, received), stallTimeout),
        );
        try {
          while (await parts.moveNext()) {
            received += parts.current.length;
            yield parts.current;
          }
        } on DownloadBlockedException {
          // Las direcciones de YouTube vencen a las pocas horas, y una vencida
          // también responde 403: en un video de horas pasa a mitad de camino.
          // Se pide una nueva una vez; si desde el mismo byte sigue el 403,
          // es un bloqueo, y reintentar no lo cambia.
          if (renewedAt == received) rethrow;
          renewedAt = received;
          current = await _refreshed(yt, videoId, current);
          continue;
        } on Object catch (error) {
          if (!_isResumable(error)) {
            if (_isNetworkFailure(error)) throw _networkFailure(error);
            rethrow;
          }
          stopped = error;
        } finally {
          unawaited(parts.cancel());
        }
        // Terminó entera, o el servidor no dice cuánto pesa y terminó.
        if (stopped == null && (total <= 0 || received >= total)) return;

        failures = received > before ? 0 : failures + 1;
        if (failures > maxResumeAttempts) {
          final error = stopped ?? TimeoutException('YouTube dejó de mandar');
          if (_isNetworkFailure(error)) throw _networkFailure(error);
          // Lo único que llega acá es una traba (TimeoutException).
          throw error as TimeoutException;
        }
        await Future<void>.delayed(_backoff(failures));
        current = await _refreshed(yt, videoId, current);
      }
    } finally {
      yt.close();
    }
  }

  /// La espera antes de retomar: [resumeBackoff] y el doble en cada intento
  /// seguido sin avance, hasta medio minuto. Sin espera si hubo avance.
  Duration _backoff(int failures) {
    if (failures == 0) return Duration.zero;
    final ms = resumeBackoff.inMilliseconds * (1 << (failures - 1));
    return Duration(milliseconds: ms.clamp(0, 30000));
  }

  /// La misma pista con una dirección nueva —las de YouTube vencen—; la
  /// misma de antes si no se pudo pedir la lista.
  Future<yt_api.AudioOnlyStreamInfo> _refreshed(
    yt_api.YoutubeExplode yt,
    String videoId,
    yt_api.AudioOnlyStreamInfo current,
  ) async {
    try {
      final manifest = await _manifest(yt, videoId);
      // La misma pista es el mismo formato EN EL MISMO IDIOMA: con audio
      // doblado, varias pistas comparten el formato, y elegir solo por él
      // podía seguir la bajada en otro idioma a mitad de camino.
      for (final audio in manifest.audioOnly) {
        if (audio.tag == current.tag &&
            audio.audioTrack?.id == current.audioTrack?.id) {
          return audio;
        }
      }
      // Pedir la lista no puede romper lo que ya venía funcionando: se
      // sigue con la dirección de antes.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {}
    return current;
  }

  /// Bytes de [audio] desde [start], pedidos por bloques de
  /// [_rangeChunkBytes] con un cliente HTTP propio —uno por intento:
  /// soltarlo lo cierra en el acto, y con él la conexión trabada—.
  ///
  /// No es la bajada del paquete: ante un "prohibido" de YouTube vuelve a
  /// pedir la lista de pistas y reintenta sin fin y sin avisar —la descarga
  /// quedaba colgada—, y pide bloques de 10 MB. Medido en octubre de 2026
  /// sobre seis videos: YouTube responde 403 a todo lo que pase del comienzo
  /// de la pista en cuatro de ellos, a lo que no es su propia app. Acá un
  /// 403 se reconoce al primer bloque y se informa como
  /// [DownloadBlockedException], en vez de esperar hasta que venza.
  static Stream<List<int>> _fetchRangeFromYouTube(
    yt_api.YoutubeExplode yt,
    yt_api.AudioOnlyStreamInfo audio,
    int start,
  ) {
    final client = http.Client();
    final total = audio.size.totalBytes;

    Stream<List<int>> parts() async* {
      var from = start;
      while (from < total) {
        final to =
            (from + _rangeChunkBytes < total
                ? from + _rangeChunkBytes
                : total) -
            1;
        final response = await client.send(_rangeRequest(audio.url, from, to));
        if (response.statusCode == 403) {
          await response.stream.drain<void>();
          throw DownloadBlockedException(
            message: 'YouTube respondió 403 a los bytes $from-$to',
          );
        }
        if (response.statusCode != 206 && response.statusCode != 200) {
          await response.stream.drain<void>();
          throw http.ClientException(
            'YouTube respondió ${response.statusCode}',
            audio.url,
          );
        }
        final before = from;
        await for (final part in response.stream) {
          from += part.length;
          yield part;
        }
        // Un bloque vacío no es avance: que lo cuente el vigilante.
        if (from == before) return;
      }
    }

    late final StreamController<List<int>> controller;
    StreamSubscription<List<int>>? subscription;
    controller = StreamController<List<int>>(
      onListen: () {
        subscription = parts().listen(
          controller.add,
          onError: controller.addError,
          onDone: () {
            client.close();
            unawaited(controller.close());
          },
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () {
        client.close();
        unawaited(subscription?.cancel());
      },
    );
    return controller.stream;
  }

  /// Cuánto se pide por vez: lo mismo que el paquete y que yt-dlp para las
  /// pistas que YouTube frena —más grande, YouTube lo baja a cuentagotas—.
  static const _rangeChunkBytes = 10 * 1024 * 1024;

  /// Los bytes [from]–[to] de [url]: las direcciones de la app de Android
  /// los piden por encabezado; las demás, por parámetro —lo mismo que hace
  /// el paquete—.
  static http.Request _rangeRequest(Uri url, int from, int to) {
    if (url.queryParameters['c'] == 'ANDROID') {
      return http.Request('GET', url)..headers['Range'] = 'bytes=$from-$to';
    }
    return http.Request(
      'GET',
      url.replace(
        queryParameters: {...url.queryParameters, 'range': '$from-$to'},
      ),
    );
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

/// [source], cortado con [TimeoutException] si pasa [limit] sin que llegue
/// nada.
///
/// No es `Stream.timeout`: ese reloj se detiene mientras quien lee tiene el
/// flujo en pausa —un `StreamIterator` lo pausa entre parte y parte—, y una
/// conexión trabada después de la primera parte no vencía nunca (medido:
/// colgado). Acá el reloj mide al que manda: se reinicia con cada parte que
/// llega y se detiene solo mientras quien lee pidió esperar.
Stream<List<int>> stallGuarded(Stream<List<int>> source, Duration limit) {
  late final StreamController<List<int>> controller;
  StreamSubscription<List<int>>? subscription;
  Timer? timer;

  void arm() {
    timer?.cancel();
    timer = Timer(limit, () {
      controller.addError(TimeoutException('No llegó nada', limit));
      unawaited(subscription?.cancel());
      unawaited(controller.close());
    });
  }

  controller = StreamController<List<int>>(
    onListen: () {
      subscription = source.listen(
        (part) {
          arm();
          controller.add(part);
        },
        onError: (Object error, StackTrace stack) {
          timer?.cancel();
          controller.addError(error, stack);
        },
        onDone: () {
          timer?.cancel();
          unawaited(controller.close());
        },
      );
      arm();
    },
    onPause: () {
      timer?.cancel();
      subscription?.pause();
    },
    onResume: () {
      subscription?.resume();
      arm();
    },
    onCancel: () {
      timer?.cancel();
      // Sin esperar: una conexión trabada no termina de cancelarse nunca.
      unawaited(subscription?.cancel());
    },
  );
  return controller.stream;
}

/// Lo que se arregla volviendo a pedir: una traba, un corte de red.
bool _isResumable(Object error) =>
    error is TimeoutException || _isNetworkFailure(error);

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

/// La pista de audio original de un video entre [streams], la de mayor
/// bitrate.
///
/// YouTube dobla algunos videos a otros idiomas con IA y los ofrece como
/// pistas aparte —con `audioTrack`, y una sola marcada como la de siempre
/// (`audioIsDefault`)—. Elegir solo por bitrate podía bajar el audio en
/// inglés, árabe o portugués de un video en español (visto en 6 de los 15
/// videos de la biblioteca de ejemplo), y la transcripción salía en ese
/// idioma. Una pista sin `audioTrack` es la de un video sin doblajes: la
/// original. Si ninguna estuviera marcada, se elige entre todas, como antes.
yt_api.AudioOnlyStreamInfo originalAudioOf(
  Iterable<yt_api.AudioOnlyStreamInfo> streams,
) {
  final all = streams.toList();
  if (all.isEmpty) {
    throw StateError('El video no ofrece ninguna pista de audio');
  }
  final original = [
    for (final stream in all)
      if (stream.audioTrack == null || stream.audioTrack!.audioIsDefault)
        stream,
  ];
  final candidates = original.isEmpty ? all : original;
  return candidates.reduce(
    (best, next) =>
        next.bitrate.bitsPerSecond > best.bitrate.bitsPerSecond ? next : best,
  );
}
