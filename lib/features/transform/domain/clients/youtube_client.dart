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
  }) = _YouTubeVideoData;
}

/// De dónde salen los datos de un video.
///
/// Se abstrae para poder probar el transformador sin salir a la red. Un test
/// que dependiera de YouTube fallaría sin conexión, cambiaría de resultado
/// cuando cambie el video, y tardaría segundos en cada corrida.
// ignore: one_member_abstracts
abstract interface class YouTubeClient {
  /// Metadatos y subtítulos de un video.
  ///
  /// [preferredLanguages] se recorre en orden hasta encontrar una pista
  /// disponible; si ninguna está, se usa la primera que haya. Más vale una
  /// transcripción en otro idioma que ninguna.
  Future<YouTubeVideoData> fetchVideo(
    String videoId, {
    List<String> preferredLanguages,
  });
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
