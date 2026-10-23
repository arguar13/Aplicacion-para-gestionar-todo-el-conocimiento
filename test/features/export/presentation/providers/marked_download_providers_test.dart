import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/highlight_palette.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/features/export/data/marked/marked_document_writers.dart';
import 'package:sinapsis/features/export/domain/entities/marked_document_format.dart';
import 'package:sinapsis/features/export/presentation/providers/marked_download_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';

import '../../../../support/fake_marked_document_writer.dart';
import '../../../../support/in_memory_file_store.dart';
import '../../../../support/sample_files.dart';

void main() {
  test('los colores del documento son los de la pantalla en el tema claro', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final colors = container.read(documentMarkColorsProvider);
    final study = StudyPalette.of(Brightness.light);

    expect(colors.summary, study.summary.toARGB32());
    expect(colors.synthesis, study.synthesis.toARGB32());
    expect(colors.keyword, study.keyword.toARGB32());
    for (final color in HighlightColor.values) {
      expect(
        colors.highlightOf(color),
        HighlightPalette.light[color].toARGB32(),
      );
    }
    // Un subrayado de antes de F38, sin color: el amarillo claro.
    expect(
      colors.highlightOf(null),
      HighlightPalette.light[HighlightColor.lightYellow].toARGB32(),
    );
  });

  test('se descargan marcados el PDF, el Word, el EPUB, la página web, el '
      'texto y el Markdown, cada uno con su escritor', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final writers = container.read(markedDocumentWritersProvider);
    expect(writers[MarkedDocumentFormat.pdf], isA<PdfMarkedDocumentWriter>());
    expect(writers[MarkedDocumentFormat.docx], isA<DocxMarkedDocumentWriter>());
    expect(writers[MarkedDocumentFormat.epub], isA<EpubMarkedDocumentWriter>());
    expect(
      writers[MarkedDocumentFormat.webPage],
      isA<WebPageMarkedDocumentWriter>(),
    );
    expect(
      writers[MarkedDocumentFormat.plainText],
      isA<TextMarkedDocumentWriter>(),
    );
    expect(
      writers[MarkedDocumentFormat.markdown],
      isA<MarkdownMarkedDocumentWriter>(),
    );
  });

  group('el formato que se ofrece', () {
    late InMemoryFileStore files;

    ProviderContainer containerWith(
      Map<MarkedDocumentFormat, FakeMarkedDocumentWriter> writers,
    ) {
      final container = ProviderContainer(
        overrides: [
          fileStoreProvider.overrideWithValue(files),
          markedDocumentWritersProvider.overrideWithValue(writers),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    setUp(() => files = InMemoryFileStore());

    Future<MarkedDocumentFormat?> formatOf(
      ProviderContainer container,
      SourceKind kind,
      String? path,
    ) => container.read(
      markedDownloadFormatProvider((kind: kind, path: path)).future,
    );

    test('el del original, si hay escritor para él', () async {
      final path = await files.save(
        bytes: buildPdf(),
        suggestedName: 'a.pdf',
        id: 'i',
      );
      final container = containerWith({
        MarkedDocumentFormat.pdf: FakeMarkedDocumentWriter(),
      });

      expect(
        await formatOf(container, SourceKind.document, path),
        MarkedDocumentFormat.pdf,
      );
    });

    test('null si ese formato no tiene escritor', () async {
      final path = await files.save(
        bytes: buildPdf(),
        suggestedName: 'a.pdf',
        id: 'i',
      );
      final container = containerWith({
        MarkedDocumentFormat.docx: FakeMarkedDocumentWriter(),
      });

      expect(await formatOf(container, SourceKind.document, path), isNull);
    });

    test('null sin archivo, o si el archivo ya no está', () async {
      final container = containerWith({
        MarkedDocumentFormat.pdf: FakeMarkedDocumentWriter(),
      });

      expect(await formatOf(container, SourceKind.document, null), isNull);
      expect(
        await formatOf(container, SourceKind.document, 'originales/x/a.pdf'),
        isNull,
      );
    });
  });
}
