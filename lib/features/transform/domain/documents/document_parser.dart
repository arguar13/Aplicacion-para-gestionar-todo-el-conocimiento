import 'dart:typed_data';

import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/features/transform/domain/transformers/transform_context.dart';

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
  ///
  /// [session] es el trabajo en curso: con qué avisar el avance, cómo saber
  /// si hay que abandonar y dónde guardar lo ya hecho. Solo lo usa un
  /// formato con trabajo largo —el PDF escaneado—; el resto lo ignora.
  Future<ParsedDocument> parse(
    DocumentSource source, {
    DocumentParseSession session = DocumentParseSession.detached,
  });
}

/// El trabajo en curso de leer un documento (F21): lo que necesita un lector
/// para un trabajo largo —reconocer cientos de páginas escaneadas— sin
/// frenar la cola ni perder lo hecho si la app se cierra.
class DocumentParseSession {
  const DocumentParseSession({
    this.context = TransformContext.detached,
    Future<Map<int, String>> Function()? loadRecognizedPages,
    Future<void> Function(int page, String text)? saveRecognizedPage,
  }) : _load = loadRecognizedPages,
       _save = saveRecognizedPage;

  /// Sin cola ni avance guardado: una prueba, o un adjunto del chat.
  static const detached = DocumentParseSession();

  /// La cola: pasar al carril largo, avisar el avance, saber si abandonar.
  final TransformContext context;

  final Future<Map<int, String>> Function()? _load;
  final Future<void> Function(int page, String text)? _save;

  /// Las páginas ya reconocidas en un intento anterior: número de página
  /// (desde 0) → texto.
  Future<Map<int, String>> recognizedPages() async =>
      await _load?.call() ?? const {};

  /// Guarda que [page] ya se reconoció, con su [text].
  Future<void> saveRecognizedPage(int page, String text) async =>
      _save?.call(page, text);
}

/// Un documento por leer, sin haberlo traído a memoria todavía (F21).
///
/// Cada formato decide cuánto necesita: un PDF de cientos de páginas se abre
/// desde el disco y sus metadatos se leen del principio y del final, sin
/// pasar nunca entero por memoria; un EPUB o un DOCX —un ZIP que hay que
/// descomprimir— sí se leen enteros, y pesan decenas de megas, no cientos.
class DocumentSource {
  const DocumentSource({
    required this.name,
    required this.size,
    required Future<Uint8List> Function() readAll,
    required Future<Uint8List> Function(int start, int length) readRange,
    this.localPath,
  }) : _readAll = readAll,
       _readRange = readRange;

  /// Un documento que ya está en memoria: el que se acaba de armar en una
  /// prueba, o el que llega de un lugar que no es el almacén.
  factory DocumentSource.memory(Uint8List bytes, {String name = 'documento'}) =>
      DocumentSource(
        name: name,
        size: bytes.length,
        readAll: () async => bytes,
        readRange: (start, length) async {
          final from = start.clamp(0, bytes.length);
          final to = (start + length).clamp(from, bytes.length);
          return Uint8List.sublistView(bytes, from, to);
        },
      );

  /// El nombre del archivo, con su extensión: un `.txt` y un `.md` no tienen
  /// firma, y sin el nombre no se reconocerían.
  final String name;

  /// Cuánto pesa, en bytes.
  final int size;

  /// Dónde está en el disco del dispositivo, si está en uno —para abrirlo
  /// desde ahí—, o `null` —en la web, o en memoria—.
  final String? localPath;

  final Future<Uint8List> Function() _readAll;
  final Future<Uint8List> Function(int start, int length) _readRange;

  /// El documento entero, en memoria.
  Future<Uint8List> readAll() => _readAll();

  /// Hasta [length] bytes a partir de [start]; menos si termina antes.
  Future<Uint8List> readRange(int start, int length) =>
      _readRange(start, length);
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
