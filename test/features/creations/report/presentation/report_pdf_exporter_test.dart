import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:sinapsis/features/creations/report/domain/report_keywords.dart';
import 'package:sinapsis/features/creations/report/domain/report_markdown.dart';
import 'package:sinapsis/features/creations/report/presentation/export/report_pdf_exporter.dart';

import '../../../../support/pdf_annotations.dart';
import '../support/sample_reports.dart';

/// Las fuentes de la app, leídas del disco: lo mismo que da `rootBundle`.
Future<ByteData> _fromDisk(String asset) async =>
    ByteData.sublistView(File(asset).readAsBytesSync());

/// El PDF de un informe (F43, paso 10), leído de vuelta con PDFium: texto de
/// verdad, con las tildes y los signos de la app, las preguntas con sus
/// opciones en el orden del visor, las respuestas en una página aparte y las
/// palabras clave en rosa.
void main() {
  group('con PDFium', _tests, skip: pdfiumPath == null ? missingPdfium : null);

  // Las fuentes que usa el PDF son las que viajan en la app: las encuentra
  // `rootBundle` (sin esto, el PDF de la app no se arma).
  testWidgets('lee sus fuentes de la app', (tester) async {
    final bytes = await tester.runAsync(
      () => const ReportPdfExporter().export(report: sampleReport()),
    );
    expect(bytes!.sublist(0, 5), '%PDF-'.codeUnits);
    expect(
      (await tester.runAsync(
        () => rootBundle.load('assets/fonts/Lora-Variable.ttf'),
      ))!.lengthInBytes,
      greaterThan(100000),
    );
  });
}

void _tests() {
  const exporter = ReportPdfExporter(fonts: _fromDisk);
  const labels = ReportExportLabels(
    kicker: 'Resumen de aprendizaje · Interactivo',
    sources: 'Fuentes: Éxodo — Comentario',
  );

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

  /// Cuántos puntos rosas (el de las palabras clave) tiene la página
  /// [index], pintada a dos píxeles por punto.
  Future<int> pinkPixels(Uint8List pdf, int index) async {
    final document = await PdfDocument.openData(pdf);
    try {
      final page = document.pages[index];
      final image = await page.render(
        fullWidth: page.width * 2,
        fullHeight: page.height * 2,
        backgroundColor: 0xFFFFFFFF,
      );
      try {
        final p = image!.pixels;
        var pink = 0;
        for (var i = 0; i < p.length; i += 4) {
          // BGRA: el rosa 0xFFB3D9.
          if ((p[i + 2] - 0xFF).abs() < 6 &&
              (p[i + 1] - 0xB3).abs() < 6 &&
              (p[i] - 0xD9).abs() < 6) {
            pink++;
          }
        }
        return pink;
      } finally {
        image?.dispose();
      }
    } finally {
      await document.dispose();
    }
  }

  test(
    'es un PDF A4 de texto de verdad, con las tildes y los signos',
    () async {
      final pdf = await exporter.export(report: sampleReport(), labels: labels);
      expect(pdf.sublist(0, 5), '%PDF-'.codeUnits);
      final pages = await pagesOf(pdf);
      final first = pages.first;
      expect(first, contains('RESUMEN DE APRENDIZAJE · INTERACTIVO'));
      expect(first, contains('Éxodo: liberación y alianza'));
      expect(
        first,
        contains('De la esclavitud en Egipto a la Alianza del Sinaí.'),
      );
      expect(first, contains('Fuentes: Éxodo — Comentario'));
      expect(first, contains('Introducción'));
      expect(first, contains('Moisés y el Faraón'));
      expect(first, contains('Dejá ir a mi pueblo.'));
      // Las viñetas y la lista numerada, con su marca.
      expect(first, contains('•'));
      expect(first, contains('1.'));
      // Las negritas pierden sus asteriscos: se dibujan, no se escriben.
      expect(first, isNot(contains('**')));

      final document = await PdfDocument.openData(pdf);
      try {
        final page = document.pages.first;
        expect(page.width, closeTo(595.28, 0.5));
        expect(page.height, closeTo(841.89, 0.5));
      } finally {
        await document.dispose();
      }
    },
  );

  test('las preguntas van con sus opciones y las respuestas, aparte', () async {
    final pdf = await exporter.export(report: sampleReport(), labels: labels);
    final pages = await pagesOf(pdf);
    expect(pages.length, greaterThanOrEqualTo(2));
    final questions = pages.sublist(0, pages.length - 1).join('\n');
    expect(questions, contains('PARA PROBARTE'));
    expect(questions, contains('¿Quién guía al pueblo fuera de Egipto?'));
    expect(questions, contains('A.'));
    expect(questions, contains('D.'));
    // La respuesta no está al lado de su pregunta: va en la última página.
    expect(questions, isNot(contains('Respuestas')));
    expect(questions, isNot(contains('zarza ardiente')));
    final answers = pages.last;
    expect(answers, contains('Respuestas'));
    expect(answers, contains('1. Introducción'));
    expect(answers, contains('Moisés recibe el llamado en la zarza ardiente.'));
    expect(answers, contains('2. Moisés y el Faraón'));
    // Con el pie de cada página.
    expect(answers, contains('Página ${pages.length} de ${pages.length}'));
  });

  test('como documento, sin preguntas ni respuestas', () async {
    final pdf = await exporter.export(
      report: sampleReport(),
      interactive: false,
      labels: labels,
    );
    final text = (await pagesOf(pdf)).join('\n');
    expect(text, isNot(contains('PARA PROBARTE')));
    expect(text, isNot(contains('¿Quién guía')));
    expect(text, isNot(contains('Respuestas')));
    expect(text, contains('La Alianza del Sinaí da forma al pueblo.'));
  });

  test('el glosario: cada término con su definición', () async {
    final pdf = await exporter.export(report: sampleGlossary());
    final text = (await pagesOf(pdf)).join('\n');
    expect(text, contains('Alianza'));
    expect(text, contains('El pacto del Sinaí.'));
    expect(text, contains('Maná'));
    expect(
      text.indexOf('Maná'),
      lessThan(text.indexOf('Moisés')),
      reason: 'en el orden del informe',
    );
  });

  test('las palabras clave, en rosa; sin palabras clave, nada rosa', () async {
    final painted = await exporter.export(
      report: sampleReport(),
      keywords: ReportKeywords(const ['Sinaí', 'Moisés']),
    );
    expect(await pinkPixels(painted, 0), greaterThan(200));

    final plain = await exporter.export(report: sampleReport());
    expect(await pinkPixels(plain, 0), 0);
  });
}
