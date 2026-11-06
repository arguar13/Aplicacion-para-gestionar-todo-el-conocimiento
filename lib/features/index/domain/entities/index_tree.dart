import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/index_entry_origin.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

part 'index_tree.freezed.dart';

/// Un tema del Índice (F46, «Por tema»): su nombre y cuántos documentos del
/// Índice tiene. [spaceId] `null` es «Sin tema»: los documentos que no están
/// en ninguno, que van al final.
@freezed
sealed class IndexTopic with _$IndexTopic {
  const factory IndexTopic({
    required String? spaceId,

    /// Vacío en «Sin tema», cuyo nombre pone la pantalla.
    required String name,
    required int documentCount,
  }) = _IndexTopic;

  const IndexTopic._();

  bool get isUntopiced => spaceId == null;
}

/// Un documento del Índice: un documento procesado vivo con texto o con
/// imágenes. Lo que se ve en su fila, sin sus entradas —se leen al
/// desplegarlo ([IndexEntry])—.
@freezed
sealed class IndexDocument with _$IndexDocument {
  const factory IndexDocument({
    required String id,

    /// El título del documento, de donde ya está (`item.title`): renombrarlo
    /// se ve al instante.
    required String title,

    /// El ícono de su fila: PDF, libro, web…
    required SourceKind sourceKind,

    /// Cuándo llegó a Procesado: el punto de «Nuevo» durante siete días.
    required DateTime createdAt,

    /// Cuántos capítulos tiene: lo que sale de sus títulos o sus marcadores,
    /// sin «Texto completo» ni las imágenes.
    required int chapterCount,

    /// Cuántas imágenes tiene ya tituladas.
    required int imageCount,

    /// Si tiene la sección «Texto».
    required bool hasText,

    /// Si su texto ya está indexado. `false` mientras el relleno no llegó a
    /// él: la pantalla lo muestra con lo que tiene y lo dice.
    required bool indexed,

    /// En qué temas está, todos (decisión D): un documento con varios aparece
    /// bajo cada uno, marcado «también en…» los otros.
    required List<String> spaceIds,
  }) = _IndexDocument;

  const IndexDocument._();

  /// Los otros temas de un documento que se muestra bajo [spaceId]: lo que
  /// dice «también en…». Bajo «Sin tema» o en la lista por documento, todos.
  List<String> alsoIn(String? spaceId) => [
    for (final id in spaceIds)
      if (id != spaceId) id,
  ];
}

/// Una entrada del Índice de un documento: un capítulo, «Texto completo» o
/// una imagen. Ver `ProcessedHeadings`.
@freezed
sealed class IndexEntry with _$IndexEntry {
  const factory IndexEntry({
    /// Su clave en la base (`processed_headings.row_key`): la identidad de la
    /// fila mientras el documento no se vuelva a indexar.
    required int key,
    required String documentId,
    required IndexEntryOrigin origin,

    /// Desde 1.
    required int level,

    /// El orden entre los de su clase: los capítulos en el orden del texto, y
    /// cada imagen en su lugar de la galería.
    required int position,

    /// Vacío en «Texto completo» y en una imagen que la fuente no nombra:
    /// el nombre lo pone la pantalla («Imagen 3»).
    required String title,

    /// Dónde está en el texto propio del documento —donde lo abre el lector—
    /// y la página del texto procesado donde cae: los tres juntos o ninguno.
    int? textStart,
    int? textEnd,
    int? textPage,

    /// La página real del PDF (decisión C): la de un marcador, o la del PDF
    /// donde cae un título de la IA. La pantalla muestra «p. 47» con ella y
    /// «pág. 3» con [textPage] sin ella.
    int? pdfPage,

    /// La imagen, en una entrada de imagen: la clave de `processed_images`.
    String? imageId,
  }) = _IndexEntry;

  const IndexEntry._();

  bool get isImage => origin == IndexEntryOrigin.image;
  bool get isWholeText => origin == IndexEntryOrigin.wholeText;
}

/// Un capítulo o una imagen que coincide con lo buscado, con lo que hace falta
/// para mostrarlo en su lugar del árbol: su documento y sus temas arriba, y
/// los capítulos que lo contienen, del más alto al más cercano.
@freezed
sealed class IndexSearchHit with _$IndexSearchHit {
  const factory IndexSearchHit({
    required IndexEntry entry,
    required String documentTitle,
    required SourceKind sourceKind,
    required List<String> spaceIds,

    /// Los capítulos que contienen a [entry], del nivel 1 hacia abajo. Vacío en
    /// uno de nivel 1 y en una imagen.
    required List<IndexEntry> ancestors,
  }) = _IndexSearchHit;
}

/// Cómo va el relleno del Índice: la línea de «indexando…» mientras falta.
@freezed
sealed class IndexProgress with _$IndexProgress {
  const factory IndexProgress({
    /// Los documentos vivos con texto.
    required int documents,

    /// De esos, cuántos ya tienen sus entradas.
    required int indexedDocuments,

    /// Las imágenes que todavía no se titularon.
    required int untitledImages,
  }) = _IndexProgress;

  const IndexProgress._();

  /// Si no falta nada.
  bool get isComplete => indexedDocuments >= documents && untitledImages == 0;
}

/// Cómo se ordena la lista «Por documento».
enum IndexDocumentOrder {
  /// De la A a la Z, sin mayúsculas ni acentos.
  title,

  /// Los que llegaron a Procesado más recientemente, primero.
  recent,
}
