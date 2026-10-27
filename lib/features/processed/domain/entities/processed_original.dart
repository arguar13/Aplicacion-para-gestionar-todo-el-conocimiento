import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';

part 'processed_original.freezed.dart';

/// La copia del original de un documento procesado (F41, decisión H): un
/// archivo propio, que se abre con los visores de siempre. Ver
/// `ProcessedOriginals`.
@freezed
sealed class ProcessedOriginal with _$ProcessedOriginal {
  const factory ProcessedOriginal({
    required String documentId,

    /// La forma del procesado que guarda el archivo.
    required String renditionId,

    /// Dónde está la copia, relativa al almacén (`FileStore`): para abrirla,
    /// `FileStore.resolve` / `localPathOf`.
    required String relativePath,

    /// `pdf` —se abre en el visor de PDF—, `html` —la página archivada, en el
    /// visor de páginas— o `document` —un Word, un EPUB o un texto: el lector
    /// muestra su texto extraído—.
    required RenditionKind kind,
    required int sizeBytes,
    required DateTime copiedAt,

    /// El archivo de la fuente del que salió.
    required String sourceFilePath,
    String? mimeType,
  }) = _ProcessedOriginal;
}

/// Lo que se pinta sobre la copia del original (decisión H): lo elegido del
/// procesado —el resumen, la síntesis, las palabras clave y los fragmentos—,
/// con las posiciones del texto de la fuente, que es el texto de la copia.
///
/// Se le da al visor como lo estudiado de [sourceKey]: el mismo `sourceKey` /
/// `renditionId` del `StudyText` que ya usan los overlays (el de la forma de
/// texto de la fuente). Para que el visor de la copia pinte esto y no todo lo
/// estudiado de la fuente, la pantalla lo abre con
/// `documentStudyProvider(sourceKey)` sobreescrito por [study] en su
/// `ProviderScope`.
@freezed
sealed class ProcessedOriginalMarks with _$ProcessedOriginalMarks {
  const factory ProcessedOriginalMarks({
    /// La forma de texto de la fuente con que se corresponde la copia.
    required String sourceKey,

    /// El resumen, la síntesis y las palabras clave elegidos, como marcas de
    /// estudiar (`StudyMarkKind`): con sus colores de siempre.
    required DocumentStudy study,

    /// Los fragmentos cortados, en el orden del texto.
    required List<ProcessedSpan> fragments,
  }) = _ProcessedOriginalMarks;
}

/// Qué hacer con la copia del original al procesar (decisión H): agregar o
/// reemplazar la copian de la fuente, actualizar la vuelve a copiar solo si el
/// archivo de la fuente cambió, y quitar la saca —a la papelera del contenido,
/// de donde se recupera—.
@freezed
sealed class OriginalEdit with _$OriginalEdit {
  const factory OriginalEdit(ProcessedChange change) = _OriginalEdit;
}

/// Las secciones que se pintan sobre la copia del original: el resumen, la
/// síntesis, las palabras clave y los fragmentos.
const kSectionsMarkedOnOriginal = {
  ProcessedSection.summary,
  ProcessedSection.synthesis,
  ProcessedSection.keywords,
  ProcessedSection.fragments,
};
