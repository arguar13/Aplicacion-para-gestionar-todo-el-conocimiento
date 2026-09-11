import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Archivos de muestra armados de verdad, no bytes inventados.
///
/// Un EPUB y un DOCX construidos con el mismo empaquetador que usa cualquier
/// herramienta real ejercitan el código como lo hará un archivo del usuario:
/// con su índice de ZIP, sus longitudes de cabecera y sus nombres de entrada
/// donde de verdad van. Unos bytes escritos a mano probarían la idea que uno
/// tiene del formato, que es exactamente lo que puede estar mal.

/// Un EPUB mínimo pero válido: `mimetype` primero y sin comprimir, como manda
/// la especificación, con su OPF y sus capítulos en el orden del spine.
Uint8List buildEpub({
  String title = 'Un libro de prueba',
  String author = 'Autora de prueba',
  List<({String name, String html})> chapters = const [
    (name: 'cap1.xhtml', html: '<h1>Primero</h1><p>El primer capítulo.</p>'),
    (name: 'cap2.xhtml', html: '<h1>Segundo</h1><p>El segundo capítulo.</p>'),
  ],
  String? containerPath,
}) {
  final opfPath = containerPath ?? 'OEBPS/contenido.opf';
  final folder = opfPath.contains('/')
      ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
      : '';

  final manifest = StringBuffer();
  final spine = StringBuffer();
  for (var i = 0; i < chapters.length; i++) {
    manifest.writeln(
      '<item id="c$i" href="${chapters[i].name}" '
      'media-type="application/xhtml+xml"/>',
    );
    spine.writeln('<itemref idref="c$i"/>');
  }

  final archive = Archive()
    // La primera entrada, sin comprimir: es lo que permite reconocer un EPUB
    // sin descomprimir nada.
    ..add(
      ArchiveFile.bytes(
        'mimetype',
        Uint8List.fromList(utf8.encode('application/epub+zip')),
      )..compression = CompressionType.none,
    )
    ..add(
      _textFile('META-INF/container.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="$opfPath" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>'''),
    )
    ..add(
      _textFile(opfPath, '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>$title</dc:title>
    <dc:creator>$author</dc:creator>
    <dc:language>es</dc:language>
  </metadata>
  <manifest>
$manifest  </manifest>
  <spine>
$spine  </spine>
</package>'''),
    );

  for (final chapter in chapters) {
    archive.add(
      _textFile('$folder${chapter.name}', '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><body>
${chapter.html}
</body></html>'''),
    );
  }

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// Un DOCX mínimo pero válido, con `[Content_Types].xml` como primera entrada
/// —que es lo que escribe Word— y el cuerpo en `word/document.xml`.
Uint8List buildDocx({String documentXml = _defaultDocumentXml}) {
  final archive = Archive()
    ..add(
      _textFile('[Content_Types].xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>'''),
    )
    ..add(_textFile('word/document.xml', documentXml));

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

const _defaultDocumentXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>Un párrafo cualquiera.</w:t></w:r></w:p>
  </w:body>
</w:document>''';

/// Un ZIP que no es ni EPUB ni DOCX: para comprobar que no se confunde
/// cualquier ZIP con un documento.
Uint8List buildPlainZip() {
  final archive = Archive()..add(_textFile('notas.txt', 'hola'));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

ArchiveFile _textFile(String name, String content) =>
    ArchiveFile.bytes(name, Uint8List.fromList(utf8.encode(content)));

/// Bytes con la firma de [signature] delante y relleno detrás.
///
/// Para los formatos donde lo único que importa es la cabecera: un PNG de
/// verdad de un solo píxel no probaría nada distinto y ocuparía el archivo de
/// pruebas.
Uint8List withSignature(List<int> signature, {int padding = 64}) =>
    Uint8List.fromList([...signature, ...List.filled(padding, 0)]);
