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
import 'package:sinapsis/features/export/data/exporters/pdf_exporter.dart';
import 'package:sinapsis/features/export/domain/entities/export_format.dart';

import '../../../../support/sample_knowledge_item.dart';

/// Dónde está la librería nativa de PDFium — ver `pdf_parser_test.dart`, que
/// tiene el mismo requisito por el mismo motivo: `flutter test` corre fuera
/// del empaquetado que en la app trae el binario solo.
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
  const exporter = PdfExporter();

  group('formato', () {
    test('es PDF', () {
      expect(exporter.format, ExportFormat.pdf);
    });
  });

  group('nombre de archivo', () {
    test('usa el título saneado con extensión .pdf', () {
      final item = sampleKnowledgeItem(title: 'Título: con / caracteres?');

      expect(exporter.suggestedFileName(item), endsWith('.pdf'));
      expect(exporter.suggestedFileName(item), isNot(contains('/')));
      expect(exporter.suggestedFileName(item), isNot(contains(':')));
    });
  });

  group('los bytes que produce', () {
    test('empiezan con la cabecera de un PDF de verdad', () async {
      final bytes = await exporter.export(sampleKnowledgeItem());

      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });

  group('leyendo el PDF de vuelta con pdfrx', () {
    test('el título, el subtítulo y las notas llegan enteros', () async {
      final bytes = await exporter.export(
        sampleKnowledgeItem(notes: 'Releer el capítulo cuatro.'),
      );

      final text = await _extractText(bytes);

      expect(text, contains('La estructura de las revoluciones científicas'));
      expect(text, contains('Thomas Kuhn'));
      expect(text, contains('Releer el capítulo cuatro.'));
    }, skip: _pdfiumPath == null ? _missingPdfium : null);

    test('el contenido de las formas de texto llega entero', () async {
      final bytes = await exporter.export(
        sampleKnowledgeItem(
          renditions: [sampleTextRendition('El cuerpo del artículo.')],
        ),
      );

      final text = await _extractText(bytes);

      expect(text, contains('El cuerpo del artículo.'));
    }, skip: _pdfiumPath == null ? _missingPdfium : null);

    test(
      'sin contenido, lo dice en vez de dejar la página en blanco',
      () async {
        final bytes = await exporter.export(sampleKnowledgeItem());

        final text = await _extractText(bytes);

        expect(text, contains('Sin contenido extraído todavía.'));
      },
      skip: _pdfiumPath == null ? _missingPdfium : null,
    );

    test('la procedencia queda al pie, con la fecha y la fuente', () async {
      final bytes = await exporter.export(
        sampleKnowledgeItem(capturedAt: DateTime(2026, 9, 11)),
      );

      final text = await _extractText(bytes);

      expect(text, contains('Guardado el 2026-09-11.'));
      expect(text, contains('Fuente: https://ejemplo.org/kuhn'));
    }, skip: _pdfiumPath == null ? _missingPdfium : null);

    test('las tildes y la ñ salen igual que entraron', () async {
      const original =
          'áéíóúñ ÁÉÍÓÚÑ ¿Cómo estás? ¡Qué día! El niño y la piñata.';
      final bytes = await exporter.export(
        sampleKnowledgeItem(renditions: [sampleTextRendition(original)]),
      );

      final text = await _extractText(bytes);

      expect(text, contains(original));
    }, skip: _pdfiumPath == null ? _missingPdfium : null);

    test('un párrafo más largo que una página completa igual pasa a la '
        'siguiente, en vez de recortarse', () async {
      // Un párrafo sin ningún salto de línea, del largo de una
      // transcripción sin puntuación —el caso real que puede exceder una
      // sola página de un tirón.
      const marker = 'MARCA_DE_CIERRE_UNICA_AL_FINAL_DEL_PARRAFO';
      final paragraph =
          '${List.filled(600, 'una palabra tras otra').join(' ')} $marker';

      final bytes = await exporter.export(
        sampleKnowledgeItem(renditions: [sampleTextRendition(paragraph)]),
      );

      Pdfrx.pdfiumModulePath = _pdfiumPath;
      await pdfrxInitialize();
      final document = await PdfDocument.openData(bytes);
      try {
        expect(
          document.pages.length,
          greaterThan(1),
          reason: 'un párrafo tan largo tiene que ocupar más de una página',
        );
      } finally {
        await document.dispose();
      }

      final text = await _extractText(bytes);
      expect(text, contains(marker));
    }, skip: _pdfiumPath == null ? _missingPdfium : null);

    test('varias formas de texto generan más de una página', () async {
      final longContent = List.filled(
        80,
        'Un párrafo de relleno.',
      ).join('\n\n');

      final bytes = await exporter.export(
        sampleKnowledgeItem(
          renditions: [
            sampleTextRendition(longContent),
            sampleTextRendition(longContent, id: 'rend-2'),
          ],
        ),
      );

      Pdfrx.pdfiumModulePath = _pdfiumPath;
      await pdfrxInitialize();
      final document = await PdfDocument.openData(bytes);
      try {
        expect(document.pages.length, greaterThan(1));
      } finally {
        await document.dispose();
      }
    }, skip: _pdfiumPath == null ? _missingPdfium : null);

    test('con una bibliografía, la agrega al pie', () async {
      final bibliography = buildBibliography([
        BibliographySource(
          itemId: 'f1',
          source: CitationSource(
            title: 'Un libro citado',
            reference: const ReferenceData(
              type: ReferenceType.book,
              contributors: [Contributor(name: PersonName(family: 'García'))],
              publisher: 'Editorial',
            ),
            date: PublicationDate.ofYear(2020),
          ),
        ),
      ], style: const Apa7Style());

      final bytes = await exporter.export(
        sampleKnowledgeItem(),
        bibliography: bibliography,
      );
      final text = await _extractText(bytes);

      expect(text, contains('Referencias'));
      expect(text, contains('García'));
      expect(
        text.indexOf('Guardado el'),
        lessThan(text.indexOf('Referencias')),
      );
    }, skip: _pdfiumPath == null ? _missingPdfium : null);

    test('sin bibliografía, no agrega la sección', () async {
      final bytes = await exporter.export(sampleKnowledgeItem());

      final text = await _extractText(bytes);
      expect(text, isNot(contains('Referencias')));
    }, skip: _pdfiumPath == null ? _missingPdfium : null);
  });
}
