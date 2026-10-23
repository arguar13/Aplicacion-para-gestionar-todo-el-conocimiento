import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/design/highlight_palette.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/features/export/data/marked/marked_document_writers.dart';
import 'package:sinapsis/features/export/domain/entities/marked_document_format.dart';
import 'package:sinapsis/features/export/domain/services/document_marks_builder.dart';
import 'package:sinapsis/features/export/domain/services/marked_document_writer.dart';
import 'package:sinapsis/features/export/domain/usecases/download_marked_document_usecase.dart';
import 'package:sinapsis/features/export/presentation/providers/export_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';

/// Quién escribe los tramos marcados de cada formato (F38): cada escritor
/// real, envuelto en su adaptador (`marked_document_writers.dart`).
///
/// Mientras un formato no esté en el mapa, su original no se puede descargar
/// marcado: la tarjeta de estudio no ofrece «Descargar» y el caso de uso
/// contesta `MarkedDownloadError.unsupportedFormat`. Las pruebas lo pisan con
/// escritores de mentira.
final markedDocumentWritersProvider =
    Provider<Map<MarkedDocumentFormat, MarkedDocumentWriter>>(
      (ref) => const {
        MarkedDocumentFormat.pdf: PdfMarkedDocumentWriter(),
        MarkedDocumentFormat.docx: DocxMarkedDocumentWriter(),
        MarkedDocumentFormat.plainText: TextMarkedDocumentWriter(),
        MarkedDocumentFormat.markdown: MarkdownMarkedDocumentWriter(),
      },
    );

/// Los colores con que se marca el documento: los de la pantalla en su tema
/// claro, porque el papel es blanco también con la app en modo oscuro.
final documentMarkColorsProvider = Provider<DocumentMarkColors>((ref) {
  final study = StudyPalette.of(Brightness.light);
  const highlights = HighlightPalette.light;
  return DocumentMarkColors(
    summary: study.summary.toARGB32(),
    synthesis: study.synthesis.toARGB32(),
    keyword: study.keyword.toARGB32(),
    highlights: {
      for (final color in HighlightColor.values)
        color: highlights[color].toARGB32(),
    },
    defaultHighlight: highlights[HighlightColor.lightYellow].toARGB32(),
  );
});

final downloadMarkedDocumentUseCaseProvider =
    Provider<DownloadMarkedDocumentUseCase>((ref) {
      return DownloadMarkedDocumentUseCase(
        files: ref.watch(fileStoreProvider),
        writers: ref.watch(markedDocumentWritersProvider),
        saver: ref.watch(fileSaverProvider),
        colors: ref.watch(documentMarkColorsProvider),
      );
    });

/// De qué elemento se pregunta el formato: su procedencia y su archivo.
typedef MarkedFormatRequest = ({SourceKind kind, String? path});

/// En qué formato se descargaría el original marcado, o `null` si no se
/// puede: no es de un formato que se sepa marcar, o no hay quien lo escriba
/// (ver [markedDocumentWritersProvider]). Es lo que decide si la tarjeta de
/// estudio ofrece «Descargar».
final markedDownloadFormatProvider = FutureProvider.autoDispose
    .family<MarkedDocumentFormat?, MarkedFormatRequest>((ref, request) async {
      final path = request.path;
      final files = ref.watch(fileStoreProvider);
      final writers = ref.watch(markedDocumentWritersProvider);
      if (path == null) return null;
      final MarkedDocumentFormat? format;
      try {
        final head = await files.readHead(path);
        if (head == null) return null;
        format = markedDocumentFormatOf(
          kind: request.kind,
          head: head,
          name: p.basename(path),
        );
        // Un almacén que no responde no tiene tipo propio: sin archivo que
        // leer, no hay botón.
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {
        return null;
      }
      return writers.containsKey(format) ? format : null;
    });
