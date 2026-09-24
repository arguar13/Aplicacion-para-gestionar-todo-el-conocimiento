import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/features/citations/domain/entities/bibliography.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';
import 'package:sinapsis/features/citations/domain/services/bibliography_builder.dart';
import 'package:sinapsis/features/citations/domain/services/styles/apa7_style.dart';
import 'package:sinapsis/features/export/data/exporters/bibliography_pdf.dart';

/// Mismo requisito que `pdf_exporter_test.dart`: el motor nativo de PDFium
/// para leer el PDF de vuelta.
final _pdfiumPath = Platform.environment['PDFIUM_PATH'];

const _missingPdfium =
    r'Falta PDFIUM_PATH. Correr: export PDFIUM_PATH="$(tool/fetch_pdfium.sh)"';

Future<String> _extractText(Uint8List bytes) async {
  Pdfrx.pdfiumModulePath = _pdfiumPath;
  await pdfrxInitialize();

  final document = await PdfDocument.openData(bytes);
  try {
    final pages = <String>[];
    for (final page in document.pages) {
      pages.add((await page.loadText())?.fullText ?? '');
    }
    return pages.join('\n\n');
  } finally {
    await document.dispose();
  }
}

void main() {
  BibliographySource book(String id, String family, String title) =>
      BibliographySource(
        itemId: id,
        source: CitationSource(
          title: title,
          reference: ReferenceData(
            type: ReferenceType.book,
            contributors: [Contributor(name: PersonName(family: family))],
            publisher: 'Editorial',
          ),
          date: PublicationDate.ofYear(2020),
        ),
      );

  group('bibliographyPdfWidgets', () {
    test('una bibliografía vacía no da ningún widget', () {
      final empty = buildBibliography(const [], style: const Apa7Style());

      expect(bibliographyPdfWidgets(empty), isEmpty);
    });
  });

  group('buildBibliographyPdf', () {
    test('empieza con la cabecera de un PDF de verdad', () async {
      final bibliography = buildBibliography([
        book('b', 'Borges', 'El Aleph'),
      ], style: const Apa7Style());

      final bytes = await buildBibliographyPdf(bibliography);

      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('trae el título de la lista y cada entrada', () async {
      final bibliography = buildBibliography([
        book('a', 'Álvarez', 'Cien años'),
        book('b', 'Borges', 'El Aleph'),
      ], style: const Apa7Style());

      final bytes = await buildBibliographyPdf(bibliography);
      final text = await _extractText(bytes);

      expect(text, contains(bibliography.title));
      expect(text, contains('Álvarez'));
      expect(text, contains('Borges'));
    }, skip: _pdfiumPath == null ? _missingPdfium : null);
  });
}
