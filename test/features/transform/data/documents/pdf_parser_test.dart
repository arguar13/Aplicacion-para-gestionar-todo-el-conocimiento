import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/features/transform/data/documents/pdf_parser.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';

import '../../../../support/sample_files.dart';

/// Dónde está la librería nativa de PDFium.
///
/// En la app la empaqueta el complemento `pdfium_flutter` y no hay nada que
/// preparar, pero `flutter test` corre fuera de ese empaquetado. La trae
/// `tool/fetch_pdfium.sh`; sin ella estas pruebas se saltan **con un motivo
/// visible**, en vez de quedar en verde sin haber probado nada.
final _pdfiumPath = Platform.environment['PDFIUM_PATH'];

const _missingPdfium =
    r'Falta PDFIUM_PATH. Correr: export PDFIUM_PATH="$(tool/fetch_pdfium.sh)"';

void main() {
  final parser = PdfParser(
    initialize: () async {
      Pdfrx.pdfiumModulePath = _pdfiumPath;
      await pdfrxInitialize();
    },
  );

  group('que sabe leer', () {
    test('solo PDF', () {
      expect(parser.canParse(FileFormat.pdf), isTrue);
      expect(parser.canParse(FileFormat.docx), isFalse);
      expect(parser.canParse(FileFormat.epub), isFalse);
    });
  });

  group('limpieza del texto de una pagina', () {
    // Se prueba aparte del motor nativo porque es lo que decide si el texto
    // de un libro entero se puede buscar o no, y merece casos precisos.

    test('une las frases partidas por el ancho de la pagina', () {
      // El salto es del diseno de la pagina, no del parrafo. Sin unirlas, el
      // indice guarda medias frases y buscar una expresion de cuatro palabras
      // no encuentra nada.
      expect(
        cleanPdfPageText('La estructura de las\nrevoluciones cientificas'),
        'La estructura de las revoluciones cientificas',
      );
    });

    test('respeta los parrafos de verdad', () {
      // Dos saltos seguidos si marcan un parrafo nuevo.
      expect(
        cleanPdfPageText('Primer parrafo.\n\nSegundo parrafo.'),
        'Primer parrafo.\n\nSegundo parrafo.',
      );
    });

    test('junta las palabras cortadas con guion', () {
      // O la palabra queda partida en dos mitades que no se encuentran nunca.
      expect(
        cleanPdfPageText('El cono-\ncimiento acumulado'),
        'El conocimiento acumulado',
      );
    });

    test('un compuesto cortado al final del renglon tambien se junta', () {
      // Costo conocido y aceptado: `teorico-practico` partido al final de una
      // linea es indistinguible de una palabra cortada. Se elige juntar
      // porque los cortes son muchisimo mas frecuentes, y porque el dano es
      // asimetrico: un compuesto sin guion se sigue leyendo y se sigue
      // encontrando; una palabra partida en dos, no.
      expect(
        cleanPdfPageText('un enfoque teorico-\npractico'),
        'un enfoque teoricopractico',
      );
    });

    test('el guion suave tambien se junta: ese si es inequivoco', () {
      // Algunos PDFs marcan el corte con el caracter invisible U+00AD, que
      // existe solo para eso.
      expect(
        cleanPdfPageText(
          'El cono\u00ADcimiento'.replaceAll('\u00AD', '\u00AD\n'),
        ),
        'El conocimiento',
      );
    });

    test('normaliza los saltos de Windows', () {
      expect(cleanPdfPageText('Una linea\r\nY otra'), 'Una linea Y otra');
    });

    test('colapsa los espacios de maquetacion', () {
      // El texto justificado llega con espacios de relleno entre palabras.
      expect(
        cleanPdfPageText('Palabras    muy      separadas'),
        'Palabras muy separadas',
      );
    });

    test('una pagina en blanco queda vacia', () {
      expect(cleanPdfPageText('   \n\n  \t '), '');
    });
  });

  group('leyendo PDFs de verdad', () {
    test('el texto de una pagina llega entero', () async {
      final result = await parser.parse(buildPdf(pageTexts: ['Hola mundo']));

      expect(result.markdown, contains('Hola mundo'));
    }, skip: _pdfiumPath == null ? _missingPdfium : null);

    test('varias paginas quedan separadas y contadas', () async {
      final result = await parser.parse(
        buildPdf(pageTexts: ['Pagina uno', 'Pagina dos', 'Pagina tres']),
      );

      expect(result.pageCount, 3);
      expect(result.markdown, contains('Pagina uno'));
      expect(result.markdown, contains('Pagina tres'));
      expect(result.markdown, contains('\n\n---\n\n'));
    }, skip: _pdfiumPath == null ? _missingPdfium : null);

    test('un PDF escaneado sale vacio, no falla', () async {
      // Un escaneo es un album de fotos de paginas: no contiene ni una letra.
      // Fallar lo pondria en rojo y ofreceria reintentar algo que no puede
      // funcionar hasta que exista el reconocimiento optico.
      final result = await parser.parse(buildPdf(pageTexts: ['', '']));

      expect(result.isEmpty, isTrue);
      expect(result.pageCount, 2);
    }, skip: _pdfiumPath == null ? _missingPdfium : null);

    test('algo que no es un PDF lanza en vez de reventar', () async {
      final basura = Uint8List.fromList(utf8.encode('esto no es un pdf'));

      await expectLater(
        parser.parse(basura),
        throwsA(isA<UnreadableDocumentException>()),
      );
    }, skip: _pdfiumPath == null ? _missingPdfium : null);
  });
}
