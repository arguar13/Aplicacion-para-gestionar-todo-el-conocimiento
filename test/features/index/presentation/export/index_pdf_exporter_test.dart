import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:sinapsis/features/index/domain/services/index_print.dart';
import 'package:sinapsis/features/index/presentation/export/index_pdf_exporter.dart';

import '../../../../support/pdf_annotations.dart';

/// Las letras de la app, leídas del disco: lo mismo que da `rootBundle`.
Future<ByteData> _fromDisk(String asset) async =>
    ByteData.sublistView(File(asset).readAsBytesSync());

String _page(int page, int pages) => 'Página $page de $pages';

const _print = IndexPrint(
  title: 'Índice',
  subtitle: 'Por tema · hasta el nivel 3 · 6 de noviembre de 2026',
  lines: [
    IndexPrintLine(kind: IndexPrintKind.topic, title: 'Roma'),
    IndexPrintLine(
      kind: IndexPrintKind.document,
      title: 'Historia de Roma',
      note: 'también en Cartago',
    ),
    IndexPrintLine(
      kind: IndexPrintKind.chapter,
      title: 'Aníbal en los Alpes',
      level: 1,
      number: '1',
      page: 'p. 47',
    ),
    IndexPrintLine(
      kind: IndexPrintKind.chapter,
      title: 'La batalla de Cannas: «el desastre»',
      level: 2,
      number: '1.1',
      page: 'p. 112',
    ),
    IndexPrintLine(kind: IndexPrintKind.wholeText, title: 'Texto completo'),
    IndexPrintLine(
      kind: IndexPrintKind.image,
      title: 'El Foro',
      level: 1,
      page: 'img. 3',
    ),
  ],
);

/// El PDF de «Descargar el índice» (F46, paso 4), leído de vuelta con
/// PDFium: texto de verdad con las tildes y los signos, el número y la
/// página de cada capítulo, los puntos guía y el pie de cada página.
void main() {
  group('con PDFium', _tests, skip: pdfiumPath == null ? missingPdfium : null);

  testWidgets('lee sus letras de la app y lo arma en otro hilo', (
    tester,
  ) async {
    final bytes = await tester.runAsync(
      () => const IndexPdfExporter().export(_print, page: _page),
    );
    expect(bytes!.sublist(0, 5), '%PDF-'.codeUnits);
  });
}

void _tests() {
  // En el mismo hilo: lo que se prueba es el PDF, no el hilo.
  Future<Uint8List> inline(
    Future<Uint8List> Function(IndexPdfJob) build,
    IndexPdfJob job,
  ) => build(job);
  final exporter = IndexPdfExporter(fonts: _fromDisk, worker: inline);

  setUpAll(() async {
    Pdfrx.pdfiumModulePath = pdfiumPath;
    await pdfrxInitialize();
  });

  Future<List<String>> pagesOf(Uint8List pdf) async {
    final document = await PdfDocument.openData(pdf);
    try {
      return [
        for (final page in document.pages)
          (await page.loadText())?.fullText ?? '',
      ];
    } finally {
      await document.dispose();
    }
  }

  /// Lo que no es blanco en la primera página entre [left] y [right]
  /// (fracciones del ancho), de arriba abajo.
  Future<int> inkBetween(Uint8List pdf, double left, double right) async {
    final document = await PdfDocument.openData(pdf);
    try {
      final page = document.pages.first;
      final width = (page.width * 3).round();
      final height = (page.height * 3).round();
      final image = await page.render(
        fullWidth: width.toDouble(),
        fullHeight: height.toDouble(),
        backgroundColor: 0xFFFFFFFF,
      );
      try {
        final p = image!.pixels;
        var ink = 0;
        for (var y = 0; y < height; y++) {
          for (var x = (width * left).round(); x < width * right; x++) {
            final i = (y * width + x) * 4;
            if (p[i] < 0xF0 || p[i + 1] < 0xF0 || p[i + 2] < 0xF0) ink++;
          }
        }
        return ink;
      } finally {
        image?.dispose();
      }
    } finally {
      await document.dispose();
    }
  }

  test(
    'el texto, con las tildes, las comillas, los números y las páginas',
    () async {
      final pdf = await exporter.export(_print, page: _page);
      final pages = await pagesOf(pdf);
      expect(pages, hasLength(1));
      final text = pages.single.replaceAll(RegExp(r'\s+'), ' ');
      for (final expected in [
        'Índice',
        'Por tema · hasta el nivel 3 · 6 de noviembre de 2026',
        'ROMA',
        'Historia de Roma',
        'también en Cartago',
        '1 Aníbal en los Alpes',
        'p. 47',
        '1.1 La batalla de Cannas: «el desastre»',
        'p. 112',
        'Texto completo',
        'El Foro',
        'img. 3',
        'Página 1 de 1',
      ]) {
        expect(text, contains(expected), reason: expected);
      }
      // La página, después del título: el renglón del índice de un libro.
      expect(text.indexOf('p. 47'), greaterThan(text.indexOf('Aníbal')));
    },
  );

  test('los puntos guía: entre un título corto y su página, y nada sin '
      'página', () async {
    IndexPrint one({String? page}) => IndexPrint(
      title: 'Í',
      subtitle: 'x',
      lines: [
        IndexPrintLine(
          kind: IndexPrintKind.chapter,
          title: 'A',
          level: 1,
          page: page,
        ),
      ],
    );
    // La franja del medio del renglón: ni el título ni la página llegan, así
    // que lo que haya ahí son los puntos.
    final dotted = await inkBetween(
      await exporter.export(one(page: 'p. 9'), page: _page),
      0.35,
      0.7,
    );
    final plain = await inkBetween(
      await exporter.export(one(), page: _page),
      0.35,
      0.7,
    );
    expect(plain, 0);
    expect(dotted, greaterThan(40), reason: '$dotted puntos');
  });

  test('un índice largo sigue en las páginas que hagan falta, cada una con '
      'su pie', () async {
    final long = IndexPrint(
      title: 'Índice',
      subtitle: 'Todo',
      lines: [
        for (var i = 1; i <= 400; i++)
          IndexPrintLine(
            kind: IndexPrintKind.chapter,
            title: 'Capítulo $i',
            level: 1 + i % 3,
            page: 'pág. $i',
          ),
      ],
    );
    final pages = [
      for (final page in await pagesOf(
        await exporter.export(long, page: _page),
      ))
        page.replaceAll(RegExp(r'\s+'), ' '),
    ];
    expect(pages.length, greaterThan(5));
    expect(pages.first, contains('Página 1 de ${pages.length}'));
    expect(pages.last, contains('Capítulo 400'));
    expect(pages.last, contains('Página ${pages.length} de ${pages.length}'));
  });
}
