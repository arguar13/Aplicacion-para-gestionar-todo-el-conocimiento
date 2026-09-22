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

  /// Nombres de capítulo que van marcados como no lineales: material
  /// auxiliar que no forma parte del hilo de lectura.
  Set<String> nonLinear = const {},

  /// Un identificador de spine que no existe en el manifiesto. Pasa en
  /// libros mal armados.
  bool withDanglingSpineEntry = false,
}) {
  final opfPath = containerPath ?? 'OEBPS/contenido.opf';
  final folder = opfPath.contains('/')
      ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
      : '';

  final manifest = StringBuffer();
  final spine = StringBuffer();
  for (var i = 0; i < chapters.length; i++) {
    manifest.writeln(
      '<item id="c$i" href="${Uri.encodeComponent(chapters[i].name)}" '
      'media-type="application/xhtml+xml"/>',
    );
    final linear = nonLinear.contains(chapters[i].name) ? ' linear="no"' : '';
    spine.writeln('<itemref idref="c$i"$linear/>');
  }
  if (withDanglingSpineEntry) {
    spine.writeln('<itemref idref="no-existe"/>');
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
///
/// [body] es el contenido de `<w:body>`: se le pasan los párrafos ya
/// escritos, que es lo que permite armar en cada prueba exactamente el caso
/// que se quiere ejercitar.
Uint8List buildDocx({String? body, String? title, String? author}) {
  final documentXml = body == null
      ? _defaultDocumentXml
      : '''
<?xml version="1.0" encoding="UTF-8"?>
<w:document xmlns:w="$wordNamespace">
  <w:body>
$body  </w:body>
</w:document>''';

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

  if (title != null || author != null) {
    archive.add(
      _textFile('docProps/core.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<cp:coreProperties
    xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
    xmlns:dc="http://purl.org/dc/elements/1.1/">
  ${title == null ? '' : '<dc:title>$title</dc:title>'}
  ${author == null ? '' : '<dc:creator>$author</dc:creator>'}
</cp:coreProperties>'''),
    );
  }

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// El espacio de nombres del formato de Word, para armar cuerpos a mano.
const wordNamespace =
    'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

/// Un párrafo de Word con un solo pedazo de texto.
///
/// [style] es el identificador del estilo (`Heading1`, `Ttulo2`), [listLevel]
/// convierte el párrafo en un punto de lista con esa sangría.
String wordParagraph(
  String text, {
  String? style,
  int? outlineLevel,
  int? listLevel,
  bool bold = false,
  bool italic = false,
}) {
  final properties = StringBuffer();
  if (style != null) properties.write('<w:pStyle w:val="$style"/>');
  if (outlineLevel != null) {
    properties.write('<w:outlineLvl w:val="$outlineLevel"/>');
  }
  if (listLevel != null) {
    properties.write(
      '<w:numPr><w:ilvl w:val="$listLevel"/><w:numId w:val="1"/></w:numPr>',
    );
  }

  final runProperties = StringBuffer();
  if (bold) runProperties.write('<w:b/>');
  if (italic) runProperties.write('<w:i/>');

  return '''
    <w:p>
      ${properties.isEmpty ? '' : '<w:pPr>$properties</w:pPr>'}
      <w:r>${runProperties.isEmpty ? '' : '<w:rPr>$runProperties</w:rPr>'}<w:t xml:space="preserve">$text</w:t></w:r>
    </w:p>
''';
}

/// Una tabla de Word a partir de sus filas.
String wordTable(List<List<String>> rows) {
  final buffer = StringBuffer('    <w:tbl>\n');
  for (final row in rows) {
    buffer.write('      <w:tr>');
    for (final cell in row) {
      buffer.write('<w:tc><w:p><w:r><w:t>$cell</w:t></w:r></w:p></w:tc>');
    }
    buffer.writeln('</w:tr>');
  }
  buffer.writeln('    </w:tbl>');
  return buffer.toString();
}

const _defaultDocumentXml =
    '''
<?xml version="1.0" encoding="UTF-8"?>
<w:document xmlns:w="$wordNamespace">
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

/// Un PDF mínimo pero válido, con una línea de texto por página.
///
/// Se arma a mano en vez de con una librería de generación: lo que se está
/// probando es la lectura de PDFs de verdad, y un PDF escrito byte a byte
/// —con su tabla de referencias cruzadas calculada— ejercita el mismo camino
/// que un archivo del usuario. Además deja controlar exactamente qué hay en
/// cada página, que con un motor de maquetación no se puede.
///
/// El texto tiene que ser ASCII: las cadenas de un PDF se codifican según la
/// fuente, y meter acentos acá obligaría a incrustar una tabla de
/// codificación que no aporta nada a lo que se quiere probar.
///
/// Una página con [pageTexts] vacío no lleva texto: es el caso del PDF
/// escaneado, que es un álbum de fotos de páginas y no contiene ni una letra.
///
/// Con [info] agrega un diccionario `Info` —`/Title (...)`, `/Author (...)`—
/// referenciado desde el `trailer`, como el que escribe cualquier programa
/// que guarda esos datos: es lo que `readPdfMetadata` (F15) sabe leer.
Uint8List buildPdf({
  List<String> pageTexts = const ['Hola mundo'],
  Map<String, String>? info,
}) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '', // el de las páginas se completa abajo, cuando se sabe cuántas hay
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];

  final pageRefs = <String>[];
  for (var i = 0; i < pageTexts.length; i++) {
    final pageNumber = objects.length + 1;
    final contentNumber = pageNumber + 1;
    pageRefs.add('$pageNumber 0 R');

    final stream = pageTexts[i].isEmpty
        ? ''
        : 'BT /F1 24 Tf 72 700 Td (${_escapePdfString(pageTexts[i])}) Tj ET';

    objects
      ..add(
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Resources << /Font << /F1 3 0 R >> >> '
        '/Contents $contentNumber 0 R >>',
      )
      ..add('<< /Length ${stream.length} >>\nstream\n$stream\nendstream');
  }

  objects[1] =
      '<< /Type /Pages /Kids [${pageRefs.join(' ')}] '
      '/Count ${pageTexts.length} >>';

  String? infoRef;
  if (info != null && info.isNotEmpty) {
    infoRef = '${objects.length + 1} 0 R';
    final fields = [
      for (final entry in info.entries)
        '/${entry.key} (${_escapePdfString(entry.value)})',
    ].join(' ');
    objects.add('<< $fields >>');
  }

  // El cuerpo, anotando dónde empieza cada objeto: la tabla de referencias
  // cruzadas son esas posiciones, y un byte de diferencia deja el archivo
  // ilegible.
  final body = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(body.length);
    body.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }

  final xrefOffset = body.length;
  body
    ..write('xref\n0 ${objects.length + 1}\n')
    // La entrada cero es siempre la cabeza de la lista de libres.
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    body.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }

  body.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R'
    '${infoRef == null ? '' : ' /Info $infoRef'} >>\n'
    'startxref\n$xrefOffset\n%%EOF\n',
  );

  // Latin-1 y no UTF-8: las posiciones de la tabla se cuentan en bytes, y con
  // UTF-8 un carácter podría ocupar dos y correr todo lo que viene después.
  return Uint8List.fromList(latin1.encode(body.toString()));
}

String _escapePdfString(String text) =>
    text.replaceAll(r'\', r'\\').replaceAll('(', r'\(').replaceAll(')', r'\)');
