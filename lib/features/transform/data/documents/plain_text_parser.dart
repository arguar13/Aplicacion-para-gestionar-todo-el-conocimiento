import 'dart:convert';
import 'dart:typed_data';

import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';

/// Lee un archivo de texto suelto o de Markdown.
///
/// No hay nada que interpretar: los bytes ya son el contenido. Existe igual
/// porque sin él un `.txt` arrastrado a la app quedaría guardado y mudo — con
/// su archivo a salvo pero sin una línea de texto buscable, que es justamente
/// lo que se venía a resolver.
class PlainTextParser implements DocumentParser {
  const PlainTextParser();

  @override
  bool canParse(FileFormat format) =>
      format == FileFormat.plainText || format == FileFormat.markdown;

  @override
  Future<ParsedDocument> parse(Uint8List bytes) async {
    // `allowMalformed`: un byte suelto corrupto —o un archivo guardado en
    // Latin-1 por un editor viejo— no puede costar el resto del texto. Se
    // sustituye el carácter ilegible y se sigue, que es infinitamente mejor
    // que rechazar el archivo entero.
    final text = utf8.decode(bytes, allowMalformed: true);

    return ParsedDocument(
      markdown: _withoutByteOrderMark(text).trimRight(),
      title: _firstHeading(text),
    );
  }

  /// El título de un Markdown, si su primera línea con contenido es uno.
  ///
  /// Solo eso: en un archivo de texto suelto, la primera línea puede ser
  /// cualquier cosa, y el nombre del archivo suele decir más. En un Markdown
  /// que empieza con `# Algo`, ese `Algo` es el título de verdad.
  String? _firstHeading(String text) {
    for (final line in text.split('\n')) {
      final trimmed = _withoutByteOrderMark(line).trim();
      if (trimmed.isEmpty) continue;

      final heading = RegExp(r'^#{1,6}\s+(.*)$').firstMatch(trimmed);
      return heading?.group(1)?.trim();
    }
    return null;
  }

  /// Quita la marca de orden de bytes que Windows pone al principio.
  ///
  /// Es invisible, pero cuenta como carácter: sin quitarla, `﻿# Título`
  /// no coincide con el patrón de encabezado y el título se pierde por un
  /// carácter que nadie ve.
  String _withoutByteOrderMark(String text) =>
      text.startsWith('﻿') ? text.substring(1) : text;
}
