import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/transform/domain/services/video_text_language.dart';

/// El texto ya guardado de un video de YouTube, lo justo para saber si está en
/// su idioma (F45, paso 4): el comienzo de su texto, su título y su idioma
/// guardado. Lo guardó una versión anterior a la red de seguridad —o a F22—,
/// y puede estar en otro idioma.
@immutable
class StoredVideoText {
  const StoredVideoText({
    required this.sourceId,
    required this.title,
    required this.head,
    this.language,
    this.documentId,
    this.sourceHead,
    this.reextracting = false,
  });

  /// La fuente de la Biblioteca: lo que se vuelve a extraer.
  final String sourceId;

  /// El documento de Procesado que salió de ella, si se mira desde Procesado;
  /// `null` en la Bandeja.
  final String? documentId;

  /// El nombre del video.
  final String title;

  /// El idioma guardado de la fuente (`Source.language`).
  final String? language;

  /// El comienzo del texto que se mira: el de la fuente en la Bandeja, el de
  /// la sección «Texto» del documento en Procesado.
  final String head;

  /// En Procesado, el comienzo del texto de la fuente, que puede ya estar
  /// bien —se volvió a extraer— aunque el del documento todavía no.
  final String? sourceHead;

  /// Si la fuente se está procesando —se pidió volver a extraerla y espera o
  /// está en curso—.
  final bool reextracting;

  @override
  bool operator ==(Object other) =>
      other is StoredVideoText &&
      other.sourceId == sourceId &&
      other.documentId == documentId &&
      other.title == title &&
      other.language == language &&
      other.head == head &&
      other.sourceHead == sourceHead &&
      other.reextracting == reextracting;

  @override
  int get hashCode => Object.hash(
    sourceId,
    documentId,
    title,
    language,
    head,
    sourceHead,
    reextracting,
  );
}

/// Un video guardado con el texto en otro idioma (F45, paso 4): lo que se
/// ofrece volver a extraer.
@immutable
class ForeignVideoText {
  const ForeignVideoText({
    required this.video,
    required this.verdict,
    required this.spoken,
    required this.sourceFits,
  });

  final StoredVideoText video;

  /// En qué está, y qué se habla.
  final VideoTextForeign verdict;

  /// El idioma que se habla, si se sabe: el que se le deja a la fuente antes
  /// de volver a extraerla.
  final String? spoken;

  /// En Procesado, si el texto de la fuente ya está en su idioma: alcanza con
  /// traerlo al documento, sin volver a extraer. Siempre `false` en la
  /// Bandeja.
  final bool sourceFits;

  String get sourceId => video.sourceId;

  @override
  bool operator ==(Object other) =>
      other is ForeignVideoText &&
      other.video == video &&
      other.verdict == verdict &&
      other.spoken == spoken &&
      other.sourceFits == sourceFits;

  @override
  int get hashCode => Object.hash(video, verdict, spoken, sourceFits);
}

/// [video], si su texto no está en el idioma que se habla; `null` si está, o
/// si no hay con qué saberlo (F45, paso 4). La misma regla que se aplica al
/// guardar (`checkVideoText`), con el idioma que se habla sacado de lo que se
/// guardó: su idioma y su título (`expectedVideoLanguage`).
ForeignVideoText? foreignVideoTextOf(StoredVideoText video) {
  final spoken = expectedVideoLanguage(
    chosen: video.language,
    title: video.title,
  );
  final verdict = checkVideoText(
    video.head,
    spoken: spoken,
    title: video.title,
  );
  if (verdict is! VideoTextForeign) return null;
  final sourceHead = video.sourceHead;
  final sourceFits =
      sourceHead != null &&
      sourceHead.trim().isNotEmpty &&
      checkVideoText(sourceHead, spoken: spoken, title: video.title)
          is! VideoTextForeign;
  return ForeignVideoText(
    video: video,
    verdict: verdict,
    spoken: spoken,
    sourceFits: sourceFits,
  );
}

/// El idioma que se le deja a la fuente de [foreign] antes de volver a
/// extraerla (F45, paso 4): el guardado, salvo que sea justo el del texto
/// equivocado —lo puso una versión anterior al guardar la pista que bajó—;
/// ese se borra, y el video se transcribe en el que se sabe que se habla.
String? languageToReextract(ForeignVideoText foreign) {
  final saved = foreign.video.language;
  if (saved == null) return null;
  final primary = saved.toLowerCase().split(RegExp('[-_]')).first;
  if (primary == foreign.verdict.language) return null;
  return saved;
}
