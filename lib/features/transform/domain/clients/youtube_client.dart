import 'package:freezed_annotation/freezed_annotation.dart';

part 'youtube_client.freezed.dart';

/// Una línea de la transcripción, con el momento en que se dice.
///
/// El momento es lo que separa una transcripción de un bloque de texto: sin
/// él, encontrar la frase que a uno le interesó no dice en qué parte del
/// video estaba, y hay que volver a mirarlo entero.
@freezed
sealed class TranscriptLine with _$TranscriptLine {
  const factory TranscriptLine({
    required Duration offset,
    required String text,
  }) = _TranscriptLine;
}

/// Lo que se puede averiguar de un video.
@freezed
sealed class YouTubeVideoData with _$YouTubeVideoData {
  const factory YouTubeVideoData({
    required String title,
    String? authorName,
    String? authorChannelUrl,
    DateTime? publishedAt,
    Duration? duration,
    String? description,

    /// Vacía si el video no tiene subtítulos de ninguna clase.
    ///
    /// Que esté vacía no es un fallo: hay videos sin subtítulos, y para esos
    /// el camino es transcribir el audio (fase posterior). Mientras tanto, el
    /// título y el autor ya valen la pena.
    @Default(<TranscriptLine>[]) List<TranscriptLine> transcript,

    /// El idioma de [transcript], como código de dos letras ("es", "en"):
    /// el idioma en que se habla, salvo que no hubiera subtítulos en ese
    /// idioma. Nulo si no hay transcripción (F22).
    String? transcriptLanguage,
  }) = _YouTubeVideoData;
}

/// De dónde salen los datos de un video.
///
/// Se abstrae para poder probar el transformador sin salir a la red. Un test
/// que dependiera de YouTube fallaría sin conexión, cambiaría de resultado
/// cuando cambie el video, y tardaría segundos en cada corrida.
abstract interface class YouTubeClient {
  /// Metadatos y subtítulos de un video.
  ///
  /// Los subtítulos son los del idioma en que se HABLA en el video, hechos
  /// por una persona si los hay y si no los automáticos: nunca una
  /// traducción teniendo el original (F22). [preferredLanguages] —los que
  /// eligió el usuario para este elemento— pasan adelante de eso. Sin pista
  /// en el idioma hablado, se recorren español e inglés, y si no la primera
  /// que haya: más vale una transcripción en otro idioma que ninguna.
  Future<YouTubeVideoData> fetchVideo(
    String videoId, {
    List<String> preferredLanguages,
  });

  /// El audio del video, para escucharlo sin conexión: se baja solo si el
  /// usuario lo pide (F21, decisión B).
  ///
  /// Solo el audio y no el video completo: es lo único que hace falta para
  /// oírlo, y baja una fracción del peso. Llega **por partes**
  /// ([YouTubeAudioStream.bytes]) para guardarse directo a disco: el de un
  /// video de cuatro horas pesa cientos de MB, y juntarlo en memoria
  /// primero es justo lo que hacía que la app se quedara sin memoria.
  Future<YouTubeAudioStream> openAudio(String videoId);
}

/// El audio de un video, listo para ir guardándose a medida que llega.
class YouTubeAudioStream {
  const YouTubeAudioStream({
    required this.bytes,
    required this.fileExtension,
    this.totalBytes,
  });

  /// El contenido, por partes. Lanza si la descarga se corta o deja de
  /// llegar.
  final Stream<List<int>> bytes;

  /// Cuánto pesa en total, si YouTube lo informa: lo que permite mostrar
  /// cuánto va.
  final int? totalBytes;

  /// La extensión del contenedor —`m4a`, `webm`—, para el nombre del
  /// archivo.
  final String fileExtension;
}

/// El video no existe, es privado o fue dado de baja.
///
/// Se distingue de un fallo de red porque no tiene sentido reintentarlo: no
/// va a aparecer.
final class VideoUnavailableException implements Exception {
  const VideoUnavailableException(this.videoId);

  final String videoId;

  @override
  String toString() => 'VideoUnavailableException: $videoId';
}
