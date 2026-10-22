import 'dart:ui' show Paragraph;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/features/transform/domain/documents/pdf_page_text.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/pdf_study_overlay.dart';

void main() {
  const sep = pdfPageSeparator;
  const green = Color(0xFFC8F2C2);
  const pink = Color(0xFFFFB3D9);
  // Una página de 200 × 200 puntos, dibujada al mismo tamaño: un punto del PDF
  // es un píxel, con la y dada vuelta.
  const pageRect = Rect.fromLTWH(0, 0, 200, 200);

  /// Un renglón de 10 puntos por letra, de y 100 a 90.
  List<PdfRect> line(String text) => [
    for (var i = 0; i < text.length; i++)
      PdfRect(i * 10.0, 100, i * 10.0 + 10, 90),
  ];

  late _FakeDocument document;
  late PdfStudyOverlay overlay;

  setUp(() {
    document = _FakeDocument();
    overlay = PdfStudyOverlay(PdfViewerController());
  });

  _FakePage addPage(String text) {
    final page = _FakePage(
      document,
      document.pages.length + 1,
      PdfPageRawText(text, line(text)),
    );
    document.pages.add(page);
    return page;
  }

  _Canvas paint(_FakePage page) {
    final canvas = _Canvas();
    overlay.paintPage(canvas, pageRect, page);
    return canvas;
  }

  test('lee la página cuando hace falta pintarla —una vez— y pinta sobre '
      'sus letras, multiplicando el color con el papel', () async {
    final first = addPage('Portada');
    final second = addPage('Hola mundo');
    overlay.update(
      content: 'Portada${sep}Hola mundo',
      paints: const [
        PaintedRange(7 + sep.length, 7 + sep.length + 10, background: green),
        PaintedRange(
          7 + sep.length + 5,
          7 + sep.length + 10,
          background: pink,
          aboveHighlights: true,
        ),
      ],
      scannedNotice: 'escaneada',
    );

    expect(paint(second).rects, isEmpty);
    expect(paint(second).rects, isEmpty);
    await pumpEventQueue();

    final drawn = paint(second).rects;
    expect(second.loads, 1);
    expect(first.loads, 0);
    expect(
      [for (final (rect, _) in drawn) rect],
      const [Rect.fromLTRB(0, 100, 50, 110), Rect.fromLTRB(50, 100, 100, 110)],
    );
    expect(
      [for (final (_, p) in drawn) p.color.toARGB32()],
      [green.toARGB32(), pink.toARGB32()],
    );
    expect(drawn.every((d) => d.$2.blendMode == BlendMode.multiply), isTrue);
  });

  test('sin nada prendido no lee ni pinta', () async {
    final page = addPage('Hola');
    overlay.update(content: 'Hola', paints: const [], scannedNotice: '');

    expect(paint(page).rects, isEmpty);
    await pumpEventQueue();
    expect(page.loads, 0);
  });

  test('una página escaneada con algo resaltado lleva el aviso, y no se '
      'pinta encima', () async {
    final scanned = addPage('');
    overlay.update(
      content: 'texto reconocido',
      paints: const [PaintedRange(0, 5, background: green)],
      scannedNotice: 'Página escaneada',
    );

    paint(scanned);
    await pumpEventQueue();
    final canvas = paint(scanned);

    expect(canvas.rects, isEmpty);
    expect(canvas.notices, 1);
  });

  test('una escaneada sin nada resaltado no lleva aviso', () async {
    addPage('Hola');
    final scanned = addPage('');
    overlay.update(
      content: 'Hola${sep}texto reconocido',
      paints: const [PaintedRange(0, 4, background: green)],
      scannedNotice: 'Página escaneada',
    );

    paint(scanned);
    await pumpEventQueue();

    expect(paint(scanned).notices, 0);
  });

  test('si una página trae un separador adentro, las recorre en orden y '
      'pinta en el lugar exacto', () async {
    const first = 'uno${sep}dos';
    addPage(first);
    final second = addPage('tres');
    const start = first.length + sep.length;
    overlay.update(
      content: '$first${sep}tres',
      paints: const [PaintedRange(start, start + 4, background: green)],
      scannedNotice: '',
    );

    paint(second);
    await pumpEventQueue();
    paint(second);
    await pumpEventQueue();

    expect(paint(second).rects.map((d) => d.$1), const [
      Rect.fromLTRB(0, 100, 40, 110),
    ]);
  });

  test('si la cuenta da pero una página no coincide con su tramo, también '
      'las recorre', () async {
    // «uno\n\n---» y después el separador: por los separadores, la primera
    // página sería «uno» y la segunda «---\n\ndos».
    const first = 'uno\n\n---';
    addPage(first);
    final second = addPage('dos');
    const start = first.length + sep.length;
    overlay.update(
      content: '$first${sep}dos',
      paints: const [PaintedRange(start, start + 3, background: green)],
      scannedNotice: '',
    );

    for (var i = 0; i < 3; i++) {
      paint(second);
      await pumpEventQueue();
    }

    expect(paint(second).rects.map((d) => d.$1), const [
      Rect.fromLTRB(0, 100, 30, 110),
    ]);
  });

  test(
    'lo que se estaba leyendo para un texto que cambió se descarta',
    () async {
      final page = addPage('Hola');
      overlay.update(
        content: 'Hola',
        paints: const [PaintedRange(0, 4, background: green)],
        scannedNotice: '',
      );
      paint(page);
      overlay.update(
        content: 'Otro',
        paints: const [PaintedRange(0, 4, background: green)],
        scannedNotice: '',
      );

      for (var i = 0; i < 3; i++) {
        await pumpEventQueue();
        paint(page);
      }

      expect(paint(page).rects, isEmpty);
    },
  );

  test('con otro texto, se vuelve a ubicar todo', () async {
    final page = addPage('Hola');
    overlay.update(
      content: 'Hola',
      paints: const [PaintedRange(0, 4, background: green)],
      scannedNotice: '',
    );
    paint(page);
    await pumpEventQueue();
    expect(paint(page).rects, hasLength(1));

    overlay.update(
      content: 'Otro',
      paints: const [PaintedRange(0, 4, background: green)],
      scannedNotice: '',
    );

    expect(paint(page).rects, isEmpty);
  });
}

class _FakeDocument implements PdfDocument {
  @override
  final List<PdfPage> pages = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePage implements PdfPage {
  _FakePage(this.document, this.pageNumber, this._text);

  @override
  final PdfDocument document;

  @override
  final int pageNumber;

  final PdfPageRawText _text;
  int loads = 0;

  @override
  double get width => 200;

  @override
  double get height => 200;

  @override
  PdfPageRotation get rotation => PdfPageRotation.none;

  @override
  Future<PdfPageRawText?> loadText() async {
    loads++;
    return _text;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Anota lo que se pinta: los rectángulos de color y los avisos.
class _Canvas implements Canvas {
  final rects = <(Rect, Paint)>[];
  int notices = 0;

  @override
  void drawRect(Rect rect, Paint paint) => rects.add((rect, paint));

  @override
  void drawRRect(RRect rrect, Paint paint) => notices++;

  @override
  void drawParagraph(Paragraph paragraph, Offset offset) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
