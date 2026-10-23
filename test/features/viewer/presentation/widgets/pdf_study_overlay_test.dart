import 'dart:ui' show Paragraph;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sinapsis/core/design/highlight_palette.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/features/transform/domain/documents/pdf_page_text.dart';
import 'package:sinapsis/features/viewer/domain/services/document_highlighter.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_hand_marks.dart';
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

  test(
    'la primera página fija, sin visor ni controlador, pinta lo mismo y '
    'avisa cuando la página recién leída pide dibujarse otra vez (F39)',
    () async {
      var repaints = 0;
      overlay = PdfStudyOverlay.fixed(onRepaint: () => repaints++);
      final page = addPage('Hola mundo');
      overlay.update(
        content: 'Hola mundo',
        paints: const [PaintedRange(0, 4, background: green)],
        scannedNotice: '',
      );
      final before = repaints;

      expect(paint(page).rects, isEmpty);
      await pumpEventQueue();

      expect(repaints, greaterThan(before));
      expect(
        [for (final (rect, _) in paint(page).rects) rect],
        const [Rect.fromLTRB(0, 100, 40, 110)],
      );
      // Sin controlador no hay a qué toque responder.
      expect(overlay.offsetAt(const Offset(5, 105)), isNull);
    },
  );

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

  group('los resaltados a mano, sobre las letras (F38)', () {
    Highlight hand(
      String id,
      int start,
      int end, {
      HighlightColor? color,
      HighlightStyle style = HighlightStyle.fill,
      int minute = 0,
    }) => Highlight(
      id: id,
      renditionId: 'r',
      startOffset: start,
      endOffset: end,
      excerpt: 'x',
      createdAt: DateTime(2026, 10, 22, 10, minute),
      color: color,
      style: style,
    );

    Future<_FakePage> shown(
      String text, {
      List<PaintedRange> paints = const [],
      List<Highlight> highlights = const [],
    }) async {
      final page = addPage(text);
      overlay.update(
        content: text,
        paints: paints,
        highlights: highlights,
        scannedNotice: 'escaneada',
      );
      paint(page);
      await pumpEventQueue();
      return page;
    }

    List<(Rect, int)> drawn(_FakePage page) => [
      for (final (rect, p) in paint(page).rects) (rect, p.color.toARGB32()),
    ];

    final orange = HighlightPalette.light[HighlightColor.orange].toARGB32();

    test(
      'sin nada más, pinta con su color, multiplicando con el papel',
      () async {
        final page = await shown(
          'Hola mundo',
          highlights: [hand('a', 5, 10, color: HighlightColor.orange)],
        );

        final canvas = paint(page);
        expect(canvas.rects.map((d) => d.$1), const [
          Rect.fromLTRB(50, 100, 100, 110),
        ]);
        expect(canvas.rects.single.$2.color.toARGB32(), orange);
        expect(canvas.rects.single.$2.blendMode, BlendMode.multiply);
      },
    );

    // Un test por color: cada uno con su overlay, que se acuerda de las
    // páginas que ya vio.
    for (final color in HighlightColor.values) {
      test('el color ${color.name} se pinta sobre el PDF con el tono del '
          'papel, de fondo y de subrayado (F39)', () async {
        final page = await shown(
          'Hola mundo',
          highlights: [
            hand('fondo', 5, 10, color: color),
            hand('linea', 0, 4, color: color, style: HighlightStyle.underline),
          ],
        );

        expect(drawn(page), [
          (
            const Rect.fromLTRB(50, 100, 100, 110),
            HighlightPalette.light[color].toARGB32(),
          ),
          (
            const Rect.fromLTRB(0, 109, 40, 110),
            HighlightPalette.lineOnPaper(color).toARGB32(),
          ),
        ]);
      });
    }

    test('va encima de las oraciones y debajo de las palabras clave: donde '
        'se pisan, queda la de más arriba', () async {
      final page = await shown(
        'Hola mundo',
        paints: const [
          PaintedRange(0, 10, background: green),
          PaintedRange(4, 6, background: pink, aboveHighlights: true),
        ],
        highlights: [hand('a', 2, 8, color: HighlightColor.orange)],
      );

      expect(drawn(page), [
        (const Rect.fromLTRB(0, 100, 20, 110), green.toARGB32()),
        (const Rect.fromLTRB(20, 100, 40, 110), orange),
        (const Rect.fromLTRB(40, 100, 60, 110), pink.toARGB32()),
        (const Rect.fromLTRB(60, 100, 80, 110), orange),
        (const Rect.fromLTRB(80, 100, 100, 110), green.toARGB32()),
      ]);
    });

    test('el orden no depende de cómo vengan en la lista de paints', () async {
      final page = await shown(
        'Hola mundo',
        paints: const [
          PaintedRange(4, 6, background: pink, aboveHighlights: true),
          PaintedRange(0, 10, background: green),
        ],
        highlights: [hand('a', 2, 8, color: HighlightColor.orange)],
      );

      expect(
        [for (final (_, color) in drawn(page)) color],
        [green.toARGB32(), orange, pink.toARGB32(), orange, green.toARGB32()],
      );
    });

    test(
      'dos que se pisan: gana el más nuevo, venga en el orden que venga',
      () async {
        final page = await shown(
          'Hola mundo',
          highlights: [
            hand('nuevo', 4, 8, color: HighlightColor.violet, minute: 5),
            hand('viejo', 0, 6, color: HighlightColor.orange, minute: 1),
          ],
        );

        final violet = HighlightPalette.light[HighlightColor.violet].toARGB32();
        expect(drawn(page), [
          (const Rect.fromLTRB(0, 100, 40, 110), orange),
          (const Rect.fromLTRB(40, 100, 80, 110), violet),
        ]);
      },
    );

    test('sin color elegido, el de siempre', () async {
      final page = await shown('Hola mundo', highlights: [hand('a', 0, 4)]);

      expect(drawn(page), [
        (
          const Rect.fromLTRB(0, 100, 40, 110),
          HighlightPalette.onPaper(null).toARGB32(),
        ),
      ]);
    });

    test('subrayado es una línea debajo de las letras, de un tono más firme '
        'que el pastel, y no tapa lo que tiene abajo', () async {
      final page = await shown(
        'Hola mundo',
        paints: const [PaintedRange(0, 10, background: green)],
        highlights: [
          hand(
            'a',
            2,
            8,
            color: HighlightColor.orange,
            style: HighlightStyle.underline,
          ),
        ],
      );

      final line = HighlightPalette.lineOnPaper(
        HighlightColor.orange,
      ).toARGB32();
      expect(line, isNot(orange));
      expect(drawn(page), [
        // El resumen sigue entero, sin partirse.
        (const Rect.fromLTRB(0, 100, 100, 110), green.toARGB32()),
        // Y la línea, pegada al borde de abajo del renglón.
        (const Rect.fromLTRB(20, 109, 80, 110), line),
      ]);
    });

    test('subrayado y de fondo a la vez: cada uno en lo suyo', () async {
      final page = await shown(
        'Hola mundo',
        highlights: [
          hand('fondo', 0, 4, color: HighlightColor.violet),
          hand(
            'linea',
            0,
            4,
            color: HighlightColor.turquoise,
            style: HighlightStyle.underline,
          ),
        ],
      );

      expect(drawn(page), hasLength(2));
      expect(paint(page).rects.first.$1.height, 10);
      expect(paint(page).rects.last.$1.height, lessThan(2));
    });

    test('al cambiar los resaltados se vuelven a ubicar y a pintar', () async {
      final page = await shown(
        'Hola mundo',
        highlights: [hand('a', 0, 4, color: HighlightColor.orange)],
      );
      expect(paint(page).rects, hasLength(1));

      overlay.update(
        content: 'Hola mundo',
        paints: const [],
        highlights: [hand('b', 5, 10, color: HighlightColor.violet)],
        scannedNotice: 'escaneada',
      );

      expect(paint(page).rects.map((d) => d.$1), const [
        Rect.fromLTRB(50, 100, 100, 110),
      ]);

      overlay.update(
        content: 'Hola mundo',
        paints: const [],
        scannedNotice: 'escaneada',
      );
      expect(paint(page).rects, isEmpty);
    });

    test(
      'en una página escaneada se avisa, también por un resaltado a mano',
      () async {
        final scanned = addPage('');
        overlay.update(
          content: 'texto reconocido',
          paints: const [],
          highlights: [hand('a', 0, 5)],
          scannedNotice: 'Página escaneada',
        );
        paint(scanned);
        await pumpEventQueue();

        final canvas = paint(scanned);
        expect(canvas.rects, isEmpty);
        expect(canvas.notices, 1);
      },
    );
  });

  group('tocar un resaltado', () {
    Highlight hand(String id, int start, int end, int minute) => Highlight(
      id: id,
      renditionId: 'r',
      startOffset: start,
      endOffset: end,
      excerpt: 'x',
      createdAt: DateTime(2026, 10, 22, 10, minute),
    );

    test('el que cubre esa letra; el fin no cuenta', () {
      final stacked = stackedHighlights([hand('a', 5, 10, 0)]);

      expect(highlightAtOffset(stacked, 5)?.id, 'a');
      expect(highlightAtOffset(stacked, 9)?.id, 'a');
      expect(highlightAtOffset(stacked, 10), isNull);
      expect(highlightAtOffset(stacked, 4), isNull);
    });

    test('donde se pisan, el de encima: el más nuevo', () {
      final stacked = stackedHighlights([
        hand('nuevo', 4, 8, 9),
        hand('viejo', 0, 6, 1),
      ]);

      expect(highlightAtOffset(stacked, 5)?.id, 'nuevo');
      expect(highlightAtOffset(stacked, 2)?.id, 'viejo');
    });

    test('sin visor listo, un toque no encuentra nada', () {
      overlay.update(
        content: 'Hola',
        paints: const [],
        highlights: [hand('a', 0, 4, 0)],
        scannedNotice: '',
      );

      expect(overlay.highlightAt(const Offset(5, 5)), isNull);
    });
  });

  group('ubicar una selección sobre el PDF (F38)', () {
    /// Lo que el visor entrega al seleccionar [from]…[to] de [page].
    PdfPageTextRange selecting(_FakePage page, int from, int to) {
      final raw = page.text;
      return PdfPageTextRange(
        pageText: PdfPageText(
          pageNumber: page.pageNumber,
          fullText: raw.fullText,
          charRects: raw.charRects,
          fragments: const [],
        ),
        start: from,
        end: to,
      );
    }

    test(
      'una palabra, sin haber pintado nada: lee la página y la ubica',
      () async {
        addPage('Portada');
        final second = addPage('Hola mundo');
        overlay.update(
          content: 'Portada${sep}Hola mundo',
          paints: const [],
          scannedNotice: '',
        );

        final location = await overlay.locateSelection([
          selecting(second, 5, 10),
        ], document.pages);

        const start = 7 + sep.length;
        expect(location.found, isTrue);
        expect(location.slices, [(start: start + 5, end: start + 10)]);
        expect(second.loads, 1);
      },
    );

    test('de una página a la otra: un tramo por página, sin el separador '
        'adentro', () async {
      final first = addPage('Hola mundo');
      final second = addPage('Chau amigos');
      const content = 'Hola mundo${sep}Chau amigos';
      overlay.update(content: content, paints: const [], scannedNotice: '');

      final location = await overlay.locateSelection([
        selecting(first, 5, 10),
        selecting(second, 0, 4),
      ], document.pages);

      final slices = location.slices;
      expect(
        [for (final s in slices) content.substring(s.start, s.end)],
        ['mundo', 'Chau'],
      );
    });

    test('con un separador dentro de una página, las recorre en orden y '
        'ubica bien', () async {
      const firstText = 'uno${sep}dos';
      addPage(firstText);
      final second = addPage('tres');
      const content = '$firstText${sep}tres';
      overlay.update(content: content, paints: const [], scannedNotice: '');

      final location = await overlay.locateSelection([
        selecting(second, 0, 4),
      ], document.pages);

      expect(location.slices, [
        (start: firstText.length + sep.length, end: content.length),
      ]);
    });

    test(
      'una página escaneada no se puede resaltar: se sabe por qué',
      () async {
        final scanned = addPage('');
        overlay.update(
          content: 'texto reconocido',
          paints: const [],
          scannedNotice: '',
        );

        final location = await overlay.locateSelection([
          PdfPageTextRange(
            pageText: PdfPageText(
              pageNumber: 1,
              fullText: 'foto',
              charRects: line('foto'),
              fragments: const [],
            ),
            start: 0,
            end: 4,
          ),
        ], document.pages);

        expect(scanned.loads, 1);
        expect(location.found, isFalse);
        expect(location.issue, HighlightIssue.scanned);
      },
    );

    test('una página con un sello cuyo texto no es el guardado: no se '
        'ubica', () async {
      final stamped = addPage('sello');
      overlay.update(
        content: 'texto reconocido',
        paints: const [],
        scannedNotice: '',
      );

      final location = await overlay.locateSelection([
        selecting(stamped, 0, 5),
      ], document.pages);

      expect(location.issue, HighlightIssue.notLocated);
    });

    test('sin nada seleccionado, o solo un salto de línea, no hay qué '
        'resaltar', () async {
      final page = addPage('Hola');
      overlay.update(content: 'Hola', paints: const [], scannedNotice: '');

      expect(
        (await overlay.locateSelection(const [], document.pages)).issue,
        HighlightIssue.nothingSelected,
      );
      final blank = PdfPageTextRange(
        pageText: PdfPageText(
          pageNumber: 1,
          fullText: ' \n',
          charRects: line(' \n'),
          fragments: const [],
        ),
        start: 0,
        end: 2,
      );
      expect(
        (await overlay.locateSelection([blank], document.pages)).issue,
        HighlightIssue.nothingSelected,
      );
      expect(page.loads, 0);
    });

    test(
      'sin texto cargado o con una página que no existe: no se ubica',
      () async {
        final page = addPage('Hola');

        expect(
          (await overlay.locateSelection([
            selecting(page, 0, 4),
          ], document.pages)).issue,
          HighlightIssue.notLocated,
        );

        overlay.update(content: 'Hola', paints: const [], scannedNotice: '');
        final far = PdfPageTextRange(
          pageText: PdfPageText(
            pageNumber: 7,
            fullText: 'Hola',
            charRects: line('Hola'),
            fragments: const [],
          ),
          start: 0,
          end: 4,
        );
        expect(
          (await overlay.locateSelection([far], document.pages)).issue,
          HighlightIssue.notLocated,
        );
      },
    );

    test('lo que se ubicó queda: ubicar de nuevo no vuelve a leer', () async {
      final page = addPage('Hola mundo');
      overlay.update(
        content: 'Hola mundo',
        paints: const [],
        scannedNotice: '',
      );

      await overlay.locateSelection([selecting(page, 0, 4)], document.pages);
      await overlay.locateSelection([selecting(page, 5, 10)], document.pages);

      expect(page.loads, 1);
    });
  });
}

class _FakeDocument implements PdfDocument {
  @override
  final List<PdfPage> pages = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePage implements PdfPage {
  _FakePage(this.document, this.pageNumber, this.text);

  @override
  final PdfDocument document;

  @override
  final int pageNumber;

  final PdfPageRawText text;
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
    return text;
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
