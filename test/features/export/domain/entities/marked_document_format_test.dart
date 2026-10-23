import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/export/domain/entities/marked_document_format.dart';
import 'package:sinapsis/features/export/domain/entities/marked_document_options.dart';

import '../../../../support/sample_files.dart';

void main() {
  MarkedDocumentFormat? formatOf(
    SourceKind kind,
    Uint8List bytes, [
    String name = '',
  ]) => markedDocumentFormatOf(kind: kind, head: bytes, name: name);

  Uint8List text(String value) => Uint8List.fromList(utf8.encode(value));

  group('el formato del original, por sus bytes', () {
    test('un PDF, un Word y un EPUB se reconocen aunque el nombre mienta', () {
      expect(
        formatOf(SourceKind.document, buildPdf(), 'cosa.txt'),
        MarkedDocumentFormat.pdf,
      );
      expect(
        formatOf(SourceKind.document, buildDocx(), 'cosa.pdf'),
        MarkedDocumentFormat.docx,
      );
      expect(
        formatOf(SourceKind.document, buildEpub(), 'cosa.docx'),
        MarkedDocumentFormat.epub,
      );
    });

    test('un texto suelto y un Markdown se distinguen por el nombre', () {
      expect(
        formatOf(SourceKind.document, text('Hola'), 'notas.txt'),
        MarkedDocumentFormat.plainText,
      );
      expect(
        formatOf(SourceKind.document, text('# Hola'), 'notas.md'),
        MarkedDocumentFormat.markdown,
      );
    });

    test('una página web archivada es siempre la página web', () {
      expect(
        formatOf(SourceKind.webPage, text('<html></html>'), 'pagina.html'),
        MarkedDocumentFormat.webPage,
      );
    });

    test('lo que no se sabe marcar da null: un ZIP cualquiera, una foto, un '
        'audio', () {
      expect(formatOf(SourceKind.document, buildPlainZip(), 'a.zip'), isNull);
      expect(
        formatOf(
          SourceKind.image,
          withSignature(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
          'a.png',
        ),
        isNull,
      );
      expect(formatOf(SourceKind.audio, text('xx'), 'a.mp3'), isNull);
    });
  });

  test('la extensión de salida: un texto suelto sale como Word, y la página '
      'web, como html', () {
    expect(
      {
        for (final format in MarkedDocumentFormat.values)
          format: format.extension,
      },
      {
        MarkedDocumentFormat.pdf: 'pdf',
        MarkedDocumentFormat.docx: 'docx',
        MarkedDocumentFormat.epub: 'epub',
        MarkedDocumentFormat.webPage: 'html',
        MarkedDocumentFormat.plainText: 'docx',
        MarkedDocumentFormat.markdown: 'md',
      },
    );
  });

  group('lo elegido dicho en el nombre', () {
    test('una sola cosa', () {
      expect(const MarkedDocumentOptions(summary: true).fileLabel, 'resumen');
      expect(
        const MarkedDocumentOptions(synthesis: true).fileLabel,
        'síntesis',
      );
      expect(
        const MarkedDocumentOptions(keywords: true).fileLabel,
        'palabras clave',
      );
      expect(
        const MarkedDocumentOptions(myHighlights: true).fileLabel,
        'mis resaltados',
      );
    });

    test('varias, con «y» antes de la última', () {
      expect(
        const MarkedDocumentOptions(
          summary: true,
          myHighlights: true,
        ).fileLabel,
        'resumen y mis resaltados',
      );
      expect(
        const MarkedDocumentOptions(
          summary: true,
          synthesis: true,
          keywords: true,
        ).fileLabel,
        'resumen, síntesis y palabras clave',
      );
      expect(
        const MarkedDocumentOptions(
          summary: true,
          synthesis: true,
          keywords: true,
          myHighlights: true,
        ).fileLabel,
        'resumen, síntesis, palabras clave y mis resaltados',
      );
    });
  });

  test('intersect se queda con lo que está en las dos', () {
    expect(
      const MarkedDocumentOptions(summary: true, keywords: true).intersect(
        const MarkedDocumentOptions(keywords: true, myHighlights: true),
      ),
      const MarkedDocumentOptions(keywords: true),
    );
  });
}
