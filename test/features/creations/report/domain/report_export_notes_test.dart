import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/features/creations/report/domain/report_canonical_text.dart';
import 'package:sinapsis/features/creations/report/domain/report_export_notes.dart';
import 'package:sinapsis/features/creations/report/domain/report_markdown.dart';
import 'package:sinapsis/features/creations/report/domain/report_markup.dart';
import 'package:sinapsis/features/creations/report/presentation/export/report_pdf_exporter.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note_target.dart';

import '../../../../support/pdf_annotations.dart';
import '../support/sample_reports.dart';

/// Las notas de la persona en lo que se descarga de un informe (F45, paso
/// 8c): las del informe entero al comienzo, como notas del informe; las de
/// un pedazo, con su llamada justo después del pedazo y lo que dicen al
/// final, en el PDF y en el Markdown.
void main() {
  final report = sampleReport();
  final text = ReportText.of(report);
  const target = TextNoteTarget.creation('informe');
  var clock = 0;

  TextNote onPiece(String id, ReportTextPlace place, String excerpt, String n) {
    final part = text.partAt(place)!;
    final start = part.start + part.text.indexOf(excerpt);
    return TextNote(
      id: id,
      origin: TextNoteOrigin.note,
      target: target,
      start: start,
      end: start + excerpt.length,
      excerpt: excerpt,
      note: n,
      color: HighlightColor.lime,
      createdAt: DateTime(2026, 11, 2).add(Duration(minutes: clock++)),
      updatedAt: DateTime(2026, 11, 2),
    );
  }

  TextNote whole(String id, String n) => TextNote(
    id: id,
    origin: TextNoteOrigin.note,
    target: target,
    excerpt: '',
    note: n,
    color: HighlightColor.lime,
    createdAt: DateTime(2026, 11, 2).add(Duration(minutes: clock++)),
    updatedAt: DateTime(2026, 11, 2),
  );

  final notes = [
    whole('w-1', 'Repasar todo'),
    onPiece('p-1', const ReportTextPlace.block(0, 0), 'Moisés', 'El que guía'),
    onPiece(
      'p-2',
      const ReportTextPlace.option(0, 0, 2),
      'Josué',
      'Viene después',
    ),
    onPiece('p-3', const ReportTextPlace.question(0, 1), 'llega', 'Al Sinaí'),
    onPiece('p-4', const ReportTextPlace.title(), 'alianza', 'El pacto'),
  ];

  ReportExportNotes build({bool interactive = true}) => reportExportNotes(
    report: report,
    notes: notes,
    interactive: interactive,
    title: 'Notas del informe',
    piecesTitle: 'Notas',
  );

  group('cuáles van y dónde', () {
    test('las del informe entero al comienzo; las de un pedazo, en su parte, '
        'donde termina su pedazo', () {
      final built = build();
      expect(built.title, 'Notas del informe');
      expect(built.whole, ['Repasar todo']);
      expect(
        [for (final p in built.pieces) (p.place, p.at, p.note)],
        [
          (
            const ReportTextPlace.title(),
            'Éxodo: liberación y alianza'.length,
            'El pacto',
          ),
          (
            const ReportTextPlace.block(0, 0),
            'El libro del Éxodo cuenta cómo Moisés'.length,
            'El que guía',
          ),
          (
            const ReportTextPlace.option(0, 0, 2),
            'Josué'.length,
            'Viene después',
          ),
          (
            const ReportTextPlace.question(0, 1),
            '¿A dónde llega'.length,
            'Al Sinaí',
          ),
        ],
      );
    });

    test('en el formato de lectura, la de una pregunta o una opción va al '
        'comienzo, con el pedazo que cita', () {
      final built = build(interactive: false);
      expect(built.whole, [
        'Repasar todo',
        '«Josué» — Viene después',
        '«llega» — Al Sinaí',
      ]);
      expect(
        built.pieces.map((p) => p.place.interactiveOnly),
        everyElement(isFalse),
      );
    });

    test('sin notas, o con una que quedó sin lugar, nada', () {
      expect(
        reportExportNotes(
          report: report,
          notes: const [],
          interactive: true,
          title: 't',
          piecesTitle: 'p',
        ).isEmpty,
        isTrue,
      );
      final lost = TextNote(
        id: 'x',
        origin: TextNoteOrigin.note,
        target: target,
        excerpt: 'no está en el informe',
        note: 'Perdida',
        color: HighlightColor.lime,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      expect(
        reportExportNotes(
          report: report,
          notes: [lost],
          interactive: true,
          title: 't',
          piecesTitle: 'p',
        ).isEmpty,
        isTrue,
      );
    });
  });

  group('las llamadas', () {
    test('se numeran en el orden en que se escriben, y una nota conserva su '
        'número', () {
      final calls = ReportNoteCalls(build());
      expect(calls.callsAt(const ReportTextPlace.block(0, 0)), [
        (at: 37, number: 1),
      ]);
      expect(calls.callsAt(const ReportTextPlace.title()), [
        (at: 27, number: 2),
      ]);
      expect(calls.callsAt(const ReportTextPlace.block(0, 0)), [
        (at: 37, number: 1),
      ]);
      expect(calls.callsAt(const ReportTextPlace.block(2, 0)), isEmpty);
      expect(calls.written, ['El que guía', 'El pacto']);
    });

    test('los pedazos se parten donde va cada llamada, con su estilo', () {
      const inlines = [
        ReportInline('Hola '),
        ReportInline('mundo', bold: true),
        ReportInline(' entero.'),
      ];
      expect(reportInlinesWithCalls(inlines, const []), inlines);
      expect(
        reportInlinesWithCalls(inlines, const [
          (at: 3, number: 1),
          (at: 10, number: 2),
          (at: 99, number: 3),
        ]),
        const [
          ReportInline('Hol'),
          1,
          ReportInline('a '),
          ReportInline('mundo', bold: true),
          2,
          ReportInline(' entero.'),
          3,
        ],
      );
    });
  });

  group('en el Markdown', () {
    test('las del informe entero en una cita debajo del título; las de un '
        'pedazo como notas al pie, en el orden en que aparecen', () {
      final markdown = reportToMarkdown(report, notes: build());
      expect(
        markdown,
        startsWith(
          '# Éxodo: liberación y alianza[^nota-1]\n'
          '\n'
          '*De la esclavitud en Egipto a la Alianza del Sinaí.*\n'
          '\n'
          '> **Notas del informe**\n'
          '>\n'
          '> - Repasar todo\n',
        ),
      );
      expect(markdown, contains('cómo Moisés[^nota-2] guía'));
      expect(markdown, contains('¿A dónde llega[^nota-4] el pueblo?'));
      expect(markdown, contains('. Josué[^nota-3]\n'));
      expect(
        markdown,
        endsWith(
          '\n[^nota-1]: El pacto\n'
          '[^nota-2]: El que guía\n'
          '[^nota-3]: Viene después\n'
          '[^nota-4]: Al Sinaí\n',
        ),
      );
    });

    test('sin notas, como siempre', () {
      expect(reportToMarkdown(report), isNot(contains('[^nota')));
    });
  });

  group('en el PDF', () {
    setUpAll(() async {
      Pdfrx.pdfiumModulePath = pdfiumPath;
      await pdfrxInitialize();
    });

    test('el bloque del comienzo, cada número después de su pedazo y lo que '
        'dicen al final, antes de las respuestas', () async {
      final pdf = await ReportPdfExporter(
        fonts: (asset) async =>
            ByteData.sublistView(File(asset).readAsBytesSync()),
      ).export(report: report, notes: build());
      final document = await PdfDocument.openData(pdf);
      try {
        final pages = [
          for (final page in document.pages)
            (await page.loadText())?.fullText ?? '',
        ];
        final first = pages.first;
        expect(first, contains('NOTAS DEL INFORME'));
        expect(first, contains('Repasar todo'));
        expect(
          first.indexOf('Repasar todo'),
          greaterThan(first.indexOf('alianza')),
        );
        expect(first, contains('Moisés2'));
        expect(first, contains('Josué3'));
        final all = pages.join('\n');
        final notesAt = all.lastIndexOf('NOTAS');
        expect(notesAt, greaterThan(0), reason: all);
        expect(all.indexOf('El que guía'), greaterThan(notesAt));
        expect(all.indexOf('Viene después'), greaterThan(notesAt));
        // Las respuestas, en su página aparte, después.
        expect(pages.last, isNot(contains('El que guía')));
      } finally {
        await document.dispose();
      }
    });
  }, skip: pdfiumPath == null ? missingPdfium : null);
}
