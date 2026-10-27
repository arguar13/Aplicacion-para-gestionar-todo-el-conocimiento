import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sinapsis/features/transform/domain/documents/pdf_page_text.dart';
import 'package:sinapsis/features/viewer/domain/services/document_highlighter.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/pdf_study_overlay.dart';

import '../../../../support/sample_files.dart';

/// Dónde está la librería nativa de PDFium — ver `pdf_parser_test.dart`, que
/// tiene el mismo requisito por el mismo motivo.
final _pdfiumPath = Platform.environment['PDFIUM_PATH'];

const _missingPdfium =
    r'Falta PDFIUM_PATH. Correr: export PDFIUM_PATH="$(tool/fetch_pdfium.sh)"';

/// Ubicar lo que se selecciona sobre un PDF de verdad (F38): el texto con
/// estructura que usa el visor para seleccionar —el que reordena y suma
/// espacios— llevado al texto extraído, que es el del texto crudo de cada
/// página. Sin PDFium no hay nada que probar, y se dice por qué.
void main() {
  group(
    'la selección sobre un PDF real, en el texto extraído',
    _tests,
    skip: _pdfiumPath == null ? _missingPdfium : null,
  );
}

void _tests() {
  setUpAll(() async {
    Pdfrx.pdfiumModulePath = _pdfiumPath;
    await pdfrxInitialize();
  });

  /// El texto extraído de [pdf], como lo arma `PdfParser`: el de cada página
  /// y el separador entre una y otra.
  Future<String> extractedText(PdfDocument document) async {
    final texts = <String>[];
    for (final page in document.pages) {
      texts.add(cleanPdfPageText((await page.loadText())?.fullText ?? ''));
    }
    return texts.join(pdfPageSeparator);
  }

  /// Lo que el visor entrega al seleccionar [snippet] en la página
  /// [pageNumber].
  Future<PdfPageTextRange> select(
    PdfDocument document,
    String snippet, {
    int pageNumber = 1,
  }) async {
    final structured = await document.pages[pageNumber - 1]
        .loadStructuredText();
    final at = structured.fullText.indexOf(snippet);
    expect(at, greaterThanOrEqualTo(0), reason: 'no está «$snippet»');
    return PdfPageTextRange(
      pageText: structured,
      start: at,
      end: at + snippet.length,
    );
  }

  Future<T> withPdf<T>(
    Uint8List bytes,
    Future<T> Function(PdfDocument document) body,
  ) async {
    final document = await PdfDocument.openData(bytes);
    try {
      return await body(document);
    } finally {
      await document.dispose();
    }
  }

  PdfStudyOverlay overlayFor(String content) =>
      PdfStudyOverlay(PdfViewerController())
        ..update(content: content, paints: const [], scannedNotice: '');

  test('unas palabras de una página: el tramo del texto extraído que '
      'son esas letras', () async {
    await withPdf(
      buildPdf(pageTexts: ['Hola mundo cruel', 'Segunda pagina aqui']),
      (document) async {
        final content = await extractedText(document);
        final overlay = overlayFor(content);

        final location = await overlay.locateSelection([
          await select(document, 'mundo cruel'),
        ], document.pages);

        expect(location.found, isTrue);
        final slice = location.slices.single;
        expect(content.substring(slice.start, slice.end), 'mundo cruel');
      },
    );
  });

  test('la segunda página cae después del separador', () async {
    await withPdf(
      buildPdf(pageTexts: ['Hola mundo cruel', 'Segunda pagina aqui']),
      (document) async {
        final content = await extractedText(document);
        final overlay = overlayFor(content);

        final location = await overlay.locateSelection([
          await select(document, 'pagina', pageNumber: 2),
        ], document.pages);

        final slice = location.slices.single;
        expect(content.substring(slice.start, slice.end), 'pagina');
        expect(
          slice.start,
          'Hola mundo cruel'.length + pdfPageSeparator.length + 8,
        );
      },
    );
  });

  test('de una página a la otra: un tramo por página, sin el separador '
      'adentro', () async {
    await withPdf(
      buildPdf(pageTexts: ['Hola mundo cruel', 'Segunda pagina aqui']),
      (document) async {
        final content = await extractedText(document);
        final overlay = overlayFor(content);
        final first = await select(document, 'cruel');
        final second = await select(document, 'Segunda', pageNumber: 2);

        final location = await overlay.locateSelection([
          PdfPageTextRange(
            pageText: first.pageText,
            start: first.start,
            end: first.pageText.fullText.length,
          ),
          PdfPageTextRange(
            pageText: second.pageText,
            start: 0,
            end: second.end,
          ),
        ], document.pages);

        expect(
          [for (final s in location.slices) content.substring(s.start, s.end)],
          ['cruel', 'Segunda'],
        );
      },
    );
  });

  test('la selección entera de una página', () async {
    await withPdf(buildPdf(pageTexts: ['Hola mundo cruel']), (document) async {
      final content = await extractedText(document);
      final overlay = overlayFor(content);
      final structured = await document.pages.first.loadStructuredText();

      final location = await overlay.locateSelection([
        PdfPageTextRange(
          pageText: structured,
          start: 0,
          end: structured.fullText.length,
        ),
      ], document.pages);

      final slice = location.slices.single;
      expect(content.substring(slice.start, slice.end), content.trim());
    });
  });

  test(
    'si el texto extraído ya no es el del PDF, no se resalta a ciegas',
    () async {
      await withPdf(buildPdf(pageTexts: ['Hola mundo cruel']), (
        document,
      ) async {
        final overlay = overlayFor('Hola mundo editado a mano');

        final location = await overlay.locateSelection([
          await select(document, 'mundo'),
        ], document.pages);

        expect(location.found, isFalse);
        expect(location.issue, HighlightIssue.notLocated);
      });
    },
  );

  test('un PDF escaneado no tiene letras: nada que seleccionar, y lo que '
      'diga el OCR no se ubica ahí', () async {
    await withPdf(
      buildPdf(pageTexts: ['Hola mundo cruel', ''], scannedPages: {1}),
      (document) async {
        // El OCR puso texto en la página escaneada.
        const content =
            'Hola mundo cruel$pdfPageSeparator'
            'texto reconocido por el OCR';
        final overlay = overlayFor(content);
        final scanned = await document.pages[1].loadStructuredText();
        expect(scanned.fullText, isEmpty);

        // Con letras que el visor no tiene —lo que pasaría si pudiera
        // seleccionar—, la página igual no admite resaltar.
        final location = await overlay.locateSelection([
          PdfPageTextRange(
            pageText: PdfPageText(
              pageNumber: 2,
              fullText: 'texto',
              charRects: [
                for (var i = 0; i < 5; i++)
                  PdfRect(i * 10.0, 100, i * 10.0 + 10, 90),
              ],
              fragments: const [],
            ),
            start: 0,
            end: 5,
          ),
        ], document.pages);

        expect(location.issue, HighlightIssue.scanned);
        // Y la otra página, con letras, sí.
        final text = await overlay.locateSelection([
          await select(document, 'mundo'),
        ], document.pages);
        expect(text.found, isTrue);
      },
    );
  });

  test('lo que se lee en voz alta se ubica en su página, sobre sus letras: '
      'el rectángulo es el de la selección de esas mismas letras', () async {
    await withPdf(
      buildPdf(pageTexts: ['Hola mundo cruel', 'Segunda pagina aqui']),
      (document) async {
        final content = await extractedText(document);
        final overlay = overlayFor(content);
        final start = content.indexOf('pagina');

        final place = await overlay.placeOf((
          start: start,
          end: start + 'pagina'.length,
        ), document.pages);

        expect(place?.pageNumber, 2);
        final rect = place!.rect!;
        final selected = await select(document, 'pagina', pageNumber: 2);
        final letters = selected.pageText.charRects.sublist(
          selected.start,
          selected.end,
        );
        final left = letters.map((r) => r.left).reduce(min);
        final right = letters.map((r) => r.right).reduce(max);
        expect(rect.left, closeTo(left, 0.5));
        expect(rect.right, closeTo(right, 0.5));
        expect(rect.width, lessThan(document.pages[1].width));
      },
    );
  });

  test('en una página escaneada, solo la página', () async {
    await withPdf(
      buildPdf(pageTexts: ['Hola mundo cruel', ''], scannedPages: {1}),
      (document) async {
        const content =
            'Hola mundo cruel$pdfPageSeparator'
            'texto reconocido por el OCR';
        final overlay = overlayFor(content);
        final start = content.indexOf('texto');

        final place = await overlay.placeOf((
          start: start,
          end: start + 5,
        ), document.pages);

        expect(place, (pageNumber: 2, rect: null));
      },
    );
  });
}
