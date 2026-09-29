import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/extracted_metadata.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/features/reference/domain/services/extraction/pdf_metadata_reader.dart';

/// Un PDF mínimo, con un solo objeto de diccionario `Info` referenciado
/// desde el `trailer` —lo que `readPdfMetadata` sigue para no confundir un
/// `/Title` de verdad con el de una entrada de índice—. Sin tabla de
/// referencias cruzadas: `readPdfMetadata` no la usa, solo busca texto.
Uint8List _pdfWithInfo(String infoBody, {String before = ''}) =>
    Uint8List.fromList(
      latin1.encode(
        '%PDF-1.4\n'
        '$before'
        '1 0 obj\n<< $infoBody >>\nendobj\n'
        'trailer\n<< /Root 1 0 R /Info 1 0 R >>\n%%EOF\n',
      ),
    );

Uint8List _pdfWithXmp(String xmpFields) => Uint8List.fromList(
  latin1.encode(
    '%PDF-1.4\n'
    '2 0 obj\n<< /Type /Metadata /Subtype /XML /Length 0 >>\n'
    'stream\n<?xpacket begin="" id=""?>\n'
    '<x:xmpmeta xmlns:x="adobe:ns:meta/">\n'
    '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">\n'
    '<rdf:Description xmlns:dc="http://purl.org/dc/elements/1.1/" '
    'xmlns:prism="http://prismstandard.org/namespaces/basic/2.0/">\n'
    '$xmpFields\n'
    '</rdf:Description>\n'
    '</rdf:RDF>\n'
    '</x:xmpmeta>\n<?xpacket end="w"?>\nendstream\nendobj\n'
    'trailer\n<< /Root 1 0 R >>\n%%EOF\n',
  ),
);

/// Un PDF "grande" —por encima de [pdfMetadataWholeReadLimit]—, con relleno
/// en el medio y una tabla de referencias clásica al final, para probar la
/// lectura por tramos: [beforePadding] va antes del relleno, [afterPadding]
/// después. La tabla apunta al objeto 1, donde sea que haya quedado.
Uint8List _bigPdf({String beforePadding = '', String afterPadding = ''}) {
  final head = '%PDF-1.4\n$beforePadding';
  final padding = ' ' * (pdfMetadataWholeReadLimit + 1024);
  final body = '$head$padding$afterPadding';
  final objOffset = body.indexOf('1 0 obj');
  final xrefOffset = body.length;
  final xref =
      'xref\n0 2\n'
      '0000000000 65535 f\r\n'
      '${objOffset.toString().padLeft(10, '0')} 00000 n\r\n'
      'trailer\n<< /Root 1 0 R /Info 1 0 R /Size 2 >>\n'
      'startxref\n$xrefOffset\n%%EOF\n';
  return Uint8List.fromList(latin1.encode('$body$xref'));
}

/// Lee [bytes] como lo haría `readPdfMetadataFrom` desde el almacén, y anota
/// cuántos bytes pidió en total.
Future<(ExtractedMetadata, int)> _readByRanges(Uint8List bytes) async {
  var requested = 0;
  final metadata = await readPdfMetadataFrom(
    size: bytes.length,
    readRange: (start, length) async {
      final end = (start + length).clamp(0, bytes.length);
      requested += end - start;
      return Uint8List.sublistView(bytes, start, end);
    },
  );
  return (metadata, requested);
}

void main() {
  group('diccionario Info', () {
    test('lee el titulo, el autor y la fecha', () {
      final bytes = _pdfWithInfo(
        '/Title (Cien anos de soledad) '
        '/Author (Marquez, Gabriel) '
        '/CreationDate (D:19670605)',
      );

      final metadata = readPdfMetadata(bytes);

      expect(metadata.title, 'Cien anos de soledad');
      expect(metadata.reference.contributors, hasLength(1));
      expect(
        metadata.reference.contributors.single.name.label,
        'Marquez, Gabriel',
      );
      expect(metadata.publishedAt, DateTime(1967, 6, 5));
      expect(metadata.publicationPrecision, PublicationPrecision.day);
    });

    test('solo el ano, sin mes ni dia', () {
      final metadata = readPdfMetadata(
        _pdfWithInfo('/Title (Sin fecha completa) /CreationDate (D:1999)'),
      );

      expect(metadata.publishedAt, DateTime(1999));
      expect(metadata.publicationPrecision, PublicationPrecision.year);
    });

    test('no confunde un Title de otro objeto con el del Info', () {
      // Un `/Title` suelto en un objeto que nadie referencia desde el
      // `trailer` como `/Info` —una entrada de índice, por ejemplo— no vale.
      final bytes = _pdfWithInfo(
        '/Author (Real, Autora)',
        before: '9 0 obj\n<< /Title (Titulo de un marcador) >>\nendobj\n',
      );

      final metadata = readPdfMetadata(bytes);

      expect(metadata.title, isNull);
      expect(metadata.reference.contributors.single.name.label, 'Real, Autora');
    });

    test('decodifica los escapes: parentesis, barra y octal', () {
      final metadata = readPdfMetadata(
        _pdfWithInfo(r'/Title (Uno \(dos\) tres \\ cuatro \101\102)'),
      );

      expect(metadata.title, r'Uno (dos) tres \ cuatro AB');
    });

    test('un texto UTF-16BE —con enie— se decodifica entero', () {
      final prefix = latin1.encode('%PDF-1.4\n1 0 obj\n<< /Title (');
      final suffix = latin1.encode(
        ') >>\nendobj\ntrailer\n<< /Root 1 0 R /Info 1 0 R >>\n%%EOF\n',
      );
      final utf16 = <int>[0xFE, 0xFF];
      for (final unit in 'Espana, senor'.codeUnits) {
        utf16
          ..add((unit >> 8) & 0xFF)
          ..add(unit & 0xFF);
      }
      // El propio caracter que no es ASCII, para probar de verdad: no se
      // puede escribir en un `String` de Dart y pasar por `latin1.encode`.
      const unit = 0xF1; // 'ñ'
      utf16
        ..add((unit >> 8) & 0xFF)
        ..add(unit & 0xFF);

      final bytes = Uint8List.fromList([...prefix, ...utf16, ...suffix]);

      expect(readPdfMetadata(bytes).title, 'Espana, senorñ');
    });

    test('varios autores separados por punto y coma', () {
      final metadata = readPdfMetadata(
        _pdfWithInfo('/Author (Garcia, Ana; Lopez, Juan)'),
      );

      expect(metadata.reference.contributors.map((c) => c.name.label), [
        'Garcia, Ana',
        'Lopez, Juan',
      ]);
    });

    test('varios autores al estilo BibTeX, con "and"', () {
      final metadata = readPdfMetadata(
        _pdfWithInfo('/Author (Garcia, Ana and Lopez, Juan)'),
      );

      expect(metadata.reference.contributors.map((c) => c.name.label), [
        'Garcia, Ana',
        'Lopez, Juan',
      ]);
    });

    test('sin diccionario Info, no encuentra nada', () {
      final bytes = Uint8List.fromList(
        latin1.encode('%PDF-1.4\ntrailer\n<< /Root 1 0 R >>\n%%EOF\n'),
      );

      expect(readPdfMetadata(bytes).isEmpty, isTrue);
    });
  });

  group('XMP', () {
    test('titulo, autores y fecha de un articulo', () {
      final bytes = _pdfWithXmp('''
<dc:title><rdf:Alt><rdf:li xml:lang="x-default">El titulo del articulo</rdf:li></rdf:Alt></dc:title>
<dc:creator><rdf:Seq><rdf:li>Ana Garcia</rdf:li><rdf:li>Juan Lopez</rdf:li></rdf:Seq></dc:creator>
<prism:publicationDate>2021-03-14</prism:publicationDate>
<prism:publicationName>Revista de Prueba</prism:publicationName>
<prism:volume>12</prism:volume>
<prism:number>3</prism:number>
<prism:startingPage>45</prism:startingPage>
<prism:endingPage>67</prism:endingPage>
''');

      final metadata = readPdfMetadata(bytes);

      expect(metadata.title, 'El titulo del articulo');
      expect(metadata.reference.contributors.map((c) => c.name.displayName), [
        'Ana Garcia',
        'Juan Lopez',
      ]);
      expect(metadata.publishedAt, DateTime(2021, 3, 14));
      expect(metadata.publicationPrecision, PublicationPrecision.day);
      expect(metadata.reference.containerTitle, 'Revista de Prueba');
      expect(metadata.reference.volume, '12');
      expect(metadata.reference.issue, '3');
      expect(metadata.reference.pages, '45-67');
    });

    test('el DOI se encuentra en cualquier parte del archivo', () {
      final bytes = _pdfWithXmp(
        '<dc:title>Con DOI</dc:title>\n'
        '<prism:doi>10.1000/xyz123</prism:doi>',
      );

      expect(readPdfMetadata(bytes).reference.doi, '10.1000/xyz123');
    });

    test('el XMP gana sobre el Info cuando los dos traen el mismo dato', () {
      final xmpPart = latin1.encode(
        '2 0 obj\n<< /Type /Metadata /Subtype /XML /Length 0 >>\n'
        'stream\n<?xpacket begin="" id=""?>\n'
        '<x:xmpmeta xmlns:x="adobe:ns:meta/">\n'
        '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">\n'
        '<rdf:Description xmlns:dc="http://purl.org/dc/elements/1.1/">\n'
        '<dc:title>Titulo del XMP</dc:title>\n'
        '</rdf:Description>\n'
        '</rdf:RDF>\n'
        '</x:xmpmeta>\n<?xpacket end="w"?>\nendstream\nendobj\n',
      );
      final infoPart = latin1.encode(
        '1 0 obj\n<< /Title (Titulo del Info) >>\nendobj\n'
        'trailer\n<< /Root 1 0 R /Info 1 0 R >>\n%%EOF\n',
      );
      final bytes = Uint8List.fromList([
        ...latin1.encode('%PDF-1.4\n'),
        ...xmpPart,
        ...infoPart,
      ]);

      expect(readPdfMetadata(bytes).title, 'Titulo del XMP');
    });

    test('sin bloque XMP ni diccionario Info, no encuentra nada', () {
      final bytes = Uint8List.fromList(latin1.encode('%PDF-1.4\n%%EOF\n'));

      expect(readPdfMetadata(bytes).isEmpty, isTrue);
    });
  });

  group('un PDF grande, por tramos (F21)', () {
    test('encuentra el Info en el medio siguiendo la tabla de referencias, '
        'sin leer el archivo entero', () async {
      // El objeto queda fuera del principio y del final: solo la tabla dice
      // dónde está.
      final bytes = _bigPdf(
        beforePadding: ' ' * (2 * 1024 * 1024),
        afterPadding:
            '1 0 obj\n<< /Title (Un libro enorme) /Author (Ana Ejemplo) >>'
            '\nendobj\n${' ' * (2 * 1024 * 1024)}',
      );

      final (metadata, requested) = await _readByRanges(bytes);

      expect(metadata.title, 'Un libro enorme');
      expect(requested, lessThan(bytes.length ~/ 4));
    });

    test('el Info cerca del final', () async {
      final (metadata, _) = await _readByRanges(
        _bigPdf(afterPadding: '1 0 obj\n<< /Title (Al final) >>\nendobj\n'),
      );

      expect(metadata.title, 'Al final');
    });

    test('el XMP del principio', () async {
      final (metadata, _) = await _readByRanges(
        _bigPdf(
          beforePadding:
              '<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF>\n'
              '<rdf:Description><dc:title><rdf:Alt>\n'
              '<rdf:li xml:lang="x-default">Desde el XMP</rdf:li>\n'
              '</rdf:Alt></dc:title></rdf:Description></rdf:RDF>\n'
              '</x:xmpmeta>\n',
          afterPadding: '1 0 obj\n<< /Producer (algo) >>\nendobj\n',
        ),
      );

      expect(metadata.title, 'Desde el XMP');
    });

    test('uno chico se sigue leyendo entero, como siempre', () async {
      final bytes = _pdfWithInfo('/Title (Chico)');

      final (metadata, requested) = await _readByRanges(bytes);

      expect(metadata.title, 'Chico');
      expect(requested, bytes.length);
    });
  });
}
