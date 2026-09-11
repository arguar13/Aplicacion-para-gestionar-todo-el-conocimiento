import 'dart:typed_data';

import 'package:sinapsis/core/storage/file_format.dart';

/// Lo que se sacó de un documento.
///
/// [title] y [author] pueden venir vacíos: no todos los formatos los traen, y
/// los que los traen no siempre los tienen puestos. Cuando falten, el
/// elemento conserva el título provisional que salió del nombre del archivo,
/// que es peor pero no es nada.
class ParsedDocument {
  const ParsedDocument({
    required this.markdown,
    this.title,
    this.author,
    this.pageCount,
  });

  /// El contenido, en Markdown.
  ///
  /// Markdown y no texto plano porque un documento tiene estructura —
  /// encabezados, listas, tablas— y perderla convierte un informe en un muro
  /// de párrafos. Además es el formato de intercambio del proyecto: lo leen
  /// Obsidian, Logseq y cualquier editor, que es lo que permite que alguien
  /// abra su carpeta dentro de diez años sin esta app.
  final String markdown;

  final String? title;
  final String? author;

  /// Cuántas páginas o capítulos tenía, si el formato lo dice.
  final int? pageCount;

  bool get isEmpty => markdown.trim().isEmpty;
}

/// Sabe leer un formato de documento.
///
/// Existe como contrato aparte del transformador porque lo que cambia entre
/// un PDF, un EPUB y un DOCX es **solo** cómo se interpretan los bytes. Todo
/// lo demás —traer el archivo del almacén, decidir si hay algo que hacer,
/// armar la forma de contenido, corregir el título— es igual para los tres, y
/// escribirlo tres veces sería tres veces la misma oportunidad de
/// equivocarse.
abstract interface class DocumentParser {
  /// Si sabe leer este formato.
  bool canParse(FileFormat format);

  /// Lee el documento.
  ///
  /// Lanza [UnreadableDocumentException] si los bytes no son lo que decían
  /// ser. Que un archivo esté corrupto no es un defecto del programa: pasa
  /// con descargas cortadas y con adjuntos de correo mal reensamblados.
  Future<ParsedDocument> parse(Uint8List bytes);
}

/// El archivo no se pudo leer: estaba corrupto, cortado, o cifrado.
class UnreadableDocumentException implements Exception {
  const UnreadableDocumentException(this.format, [this.detail]);

  final FileFormat format;
  final String? detail;

  @override
  String toString() =>
      'No se pudo leer el ${format.name}${detail == null ? '' : ': $detail'}';
}

/// El archivo original ya no está en el almacén.
///
/// Distinto de que esté corrupto: acá no hay nada que leer. Pasa cuando
/// alguien vacía el almacenamiento de la app desde los ajustes del sistema.
class MissingOriginalFileException implements Exception {
  const MissingOriginalFileException(this.path);

  final String path;

  @override
  String toString() => 'El archivo original ya no está en $path';
}
