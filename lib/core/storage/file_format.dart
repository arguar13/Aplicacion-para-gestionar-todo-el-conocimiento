import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sinapsis/core/domain/entities/source_kind.dart';

/// Qué clase de archivo es.
///
/// Es distinto de [SourceKind]: este dice el *formato* —cómo están
/// codificados los bytes— y aquel dice la *procedencia*. Un PDF y un EPUB son
/// los dos `SourceKind.document`, pero se leen con código completamente
/// distinto.
enum FileFormat {
  pdf,
  epub,
  docx,
  plainText,
  markdown,
  jpeg,
  png,
  gif,
  webp,
  heic,
  mp3,
  mpeg4,
  ogg,
  wav,
  flac,

  /// No se reconoció. Se guarda igual —el archivo es la fuente y perderlo
  /// sería lo peor que podría pasar— pero nadie va a poder sacarle texto.
  unknown;

  /// De dónde se considera que viene un archivo de este formato.
  SourceKind get sourceKind => switch (this) {
    FileFormat.pdf ||
    FileFormat.epub ||
    FileFormat.docx ||
    FileFormat.plainText ||
    FileFormat.markdown => SourceKind.document,
    FileFormat.jpeg ||
    FileFormat.png ||
    FileFormat.gif ||
    FileFormat.webp ||
    FileFormat.heic => SourceKind.image,
    FileFormat.mp3 ||
    FileFormat.ogg ||
    FileFormat.wav ||
    FileFormat.flac => SourceKind.audio,
    // Un `.mp4` puede traer video o solo audio, y desde los bytes de cabecera
    // no se distingue sin leer las pistas. Se lo trata como video: si resulta
    // tener solo audio, la transcripción funciona igual.
    FileFormat.mpeg4 => SourceKind.video,
    FileFormat.unknown => SourceKind.document,
  };
}

/// Reconoce el formato de un archivo **por sus bytes**, no por su nombre.
///
/// La extensión es una sugerencia, no un hecho: la pone quien creó el
/// archivo y sobrevive a cualquier cambio de contenido. Un `.pdf` renombrado
/// a `.txt` sigue siendo un PDF, lo que llega por el botón de compartir de
/// otra app a veces no trae extensión, y un `.docx` y un `.epub` son los dos
/// un ZIP — así que confiar en el nombre para elegir con qué código leerlos
/// terminaría en un error de parseo incomprensible en vez de en un mensaje
/// claro.
///
/// [name] se usa solo para los formatos que **no tienen firma** —un `.txt` es
/// texto suelto y no empieza con nada en particular—. Cuando los bytes dicen
/// algo, ganan los bytes.
FileFormat detectFileFormat(Uint8List bytes, {String name = ''}) {
  final byMagic = _detectByMagicBytes(bytes);
  if (byMagic != null) return byMagic;

  return _detectByExtension(name);
}

// ---------------------------------------------------------------------
// Firmas
// ---------------------------------------------------------------------

FileFormat? _detectByMagicBytes(Uint8List bytes) {
  if (_startsWith(bytes, '%PDF-')) return FileFormat.pdf;
  if (_startsWith(bytes, 'OggS')) return FileFormat.ogg;
  if (_startsWith(bytes, 'fLaC')) return FileFormat.flac;
  if (_startsWith(bytes, 'ID3')) return FileFormat.mp3;
  if (_startsWith(bytes, 'GIF87a') || _startsWith(bytes, 'GIF89a')) {
    return FileFormat.gif;
  }
  if (_hasBytes(bytes, 0, const [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ])) {
    return FileFormat.png;
  }
  if (_hasBytes(bytes, 0, const [0xFF, 0xD8, 0xFF])) return FileFormat.jpeg;

  // Un MP3 sin etiqueta ID3 empieza directamente con la cabecera de la trama:
  // once bits en uno, y después la versión y la capa. Se comprueban los tres
  // valores que usan los MPEG-1/2 Layer III reales.
  if (bytes.length >= 2 &&
      bytes[0] == 0xFF &&
      (bytes[1] == 0xFB || bytes[1] == 0xF3 || bytes[1] == 0xF2)) {
    return FileFormat.mp3;
  }

  // Los contenedores RIFF —WAV y WEBP— comparten las primeras cuatro letras
  // y se distinguen por el tipo, que va después del tamaño.
  if (_startsWith(bytes, 'RIFF')) {
    if (_hasText(bytes, 8, 'WAVE')) return FileFormat.wav;
    if (_hasText(bytes, 8, 'WEBP')) return FileFormat.webp;
  }

  // Los contenedores ISO-BMFF —MP4, M4A, HEIC— no empiezan con su firma: los
  // primeros cuatro bytes son el tamaño de la caja, y la firma viene después.
  if (_hasText(bytes, 4, 'ftyp')) {
    final brand = _textAt(bytes, 8, 4);
    if (brand == 'heic' || brand == 'heix' || brand == 'mif1') {
      return FileFormat.heic;
    }
    return FileFormat.mpeg4;
  }

  if (_hasBytes(bytes, 0, const [0x50, 0x4B, 0x03, 0x04])) {
    return _detectZipFlavour(bytes);
  }

  return null;
}

/// Un DOCX y un EPUB son los dos un ZIP: hay que mirar adentro.
FileFormat _detectZipFlavour(Uint8List bytes) {
  // La especificación de EPUB obliga a que la primera entrada del ZIP se
  // llame `mimetype` y contenga exactamente `application/epub+zip`, sin
  // comprimir. Eso permite reconocerlo leyendo la primera entrada, sin
  // descomprimir nada.
  final firstEntry = _firstZipEntry(bytes);
  if (firstEntry != null) {
    if (firstEntry.name == 'mimetype' &&
        firstEntry.content.startsWith('application/epub+zip')) {
      return FileFormat.epub;
    }
    if (firstEntry.name == '[Content_Types].xml') {
      // Es un documento de Office. Cuál de todos lo dice qué carpeta trae.
      return _containsText(bytes, 'word/document.xml')
          ? FileFormat.docx
          : FileFormat.unknown;
    }
  }

  // Camino de respaldo: un ZIP armado por otra herramienta puede no respetar
  // el orden de las entradas. Los nombres de archivo viven sin comprimir en
  // el índice del ZIP, así que buscarlos en los bytes crudos funciona igual.
  if (_containsText(bytes, 'word/document.xml')) return FileFormat.docx;
  if (_containsText(bytes, 'META-INF/container.xml')) return FileFormat.epub;

  return FileFormat.unknown;
}

/// Nombre y comienzo del contenido de la primera entrada de un ZIP.
///
/// La cabecera local mide 30 bytes fijos y después vienen, en este orden, el
/// nombre y el campo extra; sus longitudes están en la propia cabecera. Se
/// leen en vez de darlas por sentadas porque el campo extra no siempre está
/// vacío.
({String name, String content})? _firstZipEntry(Uint8List bytes) {
  const headerSize = 30;
  if (bytes.length < headerSize) return null;

  final nameLength = bytes[26] | (bytes[27] << 8);
  final extraLength = bytes[28] | (bytes[29] << 8);

  final nameEnd = headerSize + nameLength;
  if (bytes.length < nameEnd) return null;

  final contentStart = nameEnd + extraLength;
  // Con 64 bytes alcanza: lo único que se lee de acá es el `mimetype` de un
  // EPUB, que mide veinte.
  final contentEnd = (contentStart + 64).clamp(contentStart, bytes.length);
  if (contentStart > bytes.length) return null;

  return (
    name: _decodeLatin1(bytes.sublist(headerSize, nameEnd)),
    content: _decodeLatin1(bytes.sublist(contentStart, contentEnd)),
  );
}

// ---------------------------------------------------------------------
// Extensiones
// ---------------------------------------------------------------------

/// Solo para los formatos sin firma reconocible.
FileFormat _detectByExtension(String name) =>
    switch (p.extension(name).toLowerCase()) {
      '.txt' || '.text' || '.log' || '.csv' => FileFormat.plainText,
      '.md' || '.markdown' || '.mdown' => FileFormat.markdown,
      _ => FileFormat.unknown,
    };

// ---------------------------------------------------------------------
// Utilidades
// ---------------------------------------------------------------------

bool _startsWith(Uint8List bytes, String signature) =>
    _hasText(bytes, 0, signature);

bool _hasText(Uint8List bytes, int offset, String text) =>
    _textAt(bytes, offset, text.length) == text;

String? _textAt(Uint8List bytes, int offset, int length) {
  if (bytes.length < offset + length) return null;
  return _decodeLatin1(bytes.sublist(offset, offset + length));
}

bool _hasBytes(Uint8List bytes, int offset, List<int> expected) {
  if (bytes.length < offset + expected.length) return false;

  for (var i = 0; i < expected.length; i++) {
    if (bytes[offset + i] != expected[i]) return false;
  }
  return true;
}

/// Busca [text] en los bytes crudos.
///
/// Se compara byte a byte y no decodificando el archivo entero a texto: un
/// binario de treinta megas no siempre es UTF-8 válido, y decodificarlo
/// costaría más memoria que el archivo.
bool _containsText(Uint8List bytes, String text) {
  final needle = ascii.encode(text);
  if (needle.isEmpty || bytes.length < needle.length) return false;

  final last = bytes.length - needle.length;
  outer:
  for (var i = 0; i <= last; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (bytes[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

/// Decodifica como latin-1 y no como UTF-8 a propósito: acá se leen firmas y
/// nombres de entrada de ZIP, que son ASCII. Latin-1 nunca lanza —cualquier
/// byte tiene un carácter— así que un archivo corrupto devuelve un nombre
/// raro en vez de tumbar la detección.
String _decodeLatin1(List<int> bytes) => latin1.decode(bytes);
