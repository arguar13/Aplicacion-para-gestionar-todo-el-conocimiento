import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/entities/attachment_download_status.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';

/// Los grupos del «Contenido» de un elemento, en el orden en que se muestran
/// y en el que se bajan cuando no entra todo (decisión E de F30): primero lo
/// que más pesa en conocimiento por byte —los documentos—, al final lo que
/// más pesa en bytes —los videos—.
enum AttachmentGroup {
  documents,
  audios,
  images,
  videos,
  others;

  static AttachmentGroup of(RenditionKind kind) => switch (kind) {
    RenditionKind.pdf ||
    RenditionKind.document ||
    RenditionKind.markdown ||
    RenditionKind.plainText ||
    RenditionKind.html => AttachmentGroup.documents,
    RenditionKind.audio => AttachmentGroup.audios,
    RenditionKind.image => AttachmentGroup.images,
    RenditionKind.video => AttachmentGroup.videos,
    RenditionKind.blocks || RenditionKind.file => AttachmentGroup.others,
  };

  /// Los grupos en el orden de la sección «Contenido»: documentos, audios,
  /// videos e imágenes, como los pidió la decisión D.
  static const displayOrder = [documents, audios, videos, images, others];
}

/// Un archivo del «Contenido» de un elemento (F30): lo bajado de una página
/// o una publicación, en su formato original.
@immutable
class Attachment {
  const Attachment({
    required this.id,
    required this.itemId,
    required this.kind,
    required this.relativePath,
    required this.position,
    required this.createdAt,
    this.title,
    this.originUrl,
    this.mimeType,
    this.sizeBytes,
    this.textLength,
  });

  /// El identificador de su forma.
  final String id;
  final String itemId;
  final RenditionKind kind;
  final String relativePath;
  final int position;
  final DateTime createdAt;

  /// Con qué nombre se lo ofrecía: el texto del enlace, el de la foto.
  final String? title;

  /// De dónde se bajó.
  final String? originUrl;
  final String? mimeType;
  final int? sizeBytes;

  /// Cuántos caracteres tiene su texto; `null` si todavía no se le sacó, y 0
  /// si se intentó y no tenía —una foto sin letras—.
  final int? textLength;

  AttachmentGroup get group => AttachmentGroup.of(kind);

  /// El nombre del archivo, como quedó guardado.
  String get fileName => relativePath.split('/').last;

  /// Lo que se muestra como nombre.
  String get displayName {
    final name = title?.trim();
    return name == null || name.isEmpty ? fileName : name;
  }

  bool get hasText => (textLength ?? 0) > 0;

  /// Si ya se intentó sacarle el texto, haya tenido o no.
  bool get textAttempted => textLength != null;

  /// Si de esta clase de archivo se puede sacar texto: los documentos se
  /// leen, los audios y videos se transcriben, las fotos se leen con OCR.
  bool get canHaveText => switch (kind) {
    RenditionKind.pdf ||
    RenditionKind.document ||
    RenditionKind.image ||
    RenditionKind.audio ||
    RenditionKind.video => true,
    _ => false,
  };

  @override
  bool operator ==(Object other) =>
      other is Attachment &&
      other.id == id &&
      other.itemId == itemId &&
      other.kind == kind &&
      other.relativePath == relativePath &&
      other.position == position &&
      other.createdAt == createdAt &&
      other.title == title &&
      other.originUrl == originUrl &&
      other.mimeType == mimeType &&
      other.sizeBytes == sizeBytes &&
      other.textLength == textLength;

  @override
  int get hashCode => Object.hash(
    id,
    itemId,
    kind,
    relativePath,
    position,
    createdAt,
    title,
    originUrl,
    mimeType,
    sizeBytes,
    textLength,
  );
}

/// Un archivo que ofrece una página y se va a intentar bajar.
@immutable
class AttachmentCandidate {
  const AttachmentCandidate({
    required this.url,
    required this.kind,
    required this.position,
    this.title,
    this.expectedBytes,
  });

  final Uri url;

  /// Qué se espera que sea, por cómo aparece en la página.
  final RenditionKind kind;

  /// En qué orden aparece.
  final int position;
  final String? title;

  /// Cuánto pesa, si ya se sabe.
  final int? expectedBytes;

  AttachmentGroup get group => AttachmentGroup.of(kind);

  @override
  bool operator ==(Object other) =>
      other is AttachmentCandidate &&
      other.url == url &&
      other.kind == kind &&
      other.position == position &&
      other.title == title &&
      other.expectedBytes == expectedBytes;

  @override
  int get hashCode => Object.hash(url, kind, position, title, expectedBytes);

  @override
  String toString() => 'AttachmentCandidate($kind, $url, "$title")';
}

/// Un renglón de la lista de trabajo: un archivo que ofrece la página y en
/// qué quedó.
@immutable
class AttachmentDownload {
  const AttachmentDownload({
    required this.id,
    required this.itemId,
    required this.url,
    required this.kind,
    required this.position,
    required this.status,
    this.title,
    this.forced = false,
    this.expectedBytes,
    this.renditionId,
  });

  final String id;
  final String itemId;
  final Uri url;
  final RenditionKind kind;
  final int position;
  final AttachmentDownloadStatus status;
  final String? title;

  /// La persona pidió «Bajar el resto»: el tope no se le aplica.
  final bool forced;

  final int? expectedBytes;
  final String? renditionId;

  AttachmentGroup get group => AttachmentGroup.of(kind);

  @override
  bool operator ==(Object other) =>
      other is AttachmentDownload &&
      other.id == id &&
      other.itemId == itemId &&
      other.url == url &&
      other.kind == kind &&
      other.position == position &&
      other.status == status &&
      other.title == title &&
      other.forced == forced &&
      other.expectedBytes == expectedBytes &&
      other.renditionId == renditionId;

  @override
  int get hashCode => Object.hash(
    id,
    itemId,
    url,
    kind,
    position,
    status,
    title,
    forced,
    expectedBytes,
    renditionId,
  );
}
