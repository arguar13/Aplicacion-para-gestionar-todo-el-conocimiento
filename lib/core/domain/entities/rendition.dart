import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/timed_word.dart';

part 'rendition.freezed.dart';

/// Una de las formas en que existe el contenido de un elemento.
///
/// Un video de YouTube puede tener tres a la vez: la transcripción, el enlace
/// y la miniatura. Que sean varias —y no un único campo `contenido`— es lo
/// que permite *elegir en qué formato conservarlo* sin tener que elegir uno
/// solo: conviven, y al exportar se toma la que haga falta.
///
/// Está partida en dos variantes en vez de tener `content` y `filePath`
/// anulables porque un estado como "las dos llenas" o "las dos vacías" no
/// significa nada, y con dos campos anulables sería representable. Acá no se
/// puede construir.
@freezed
sealed class Rendition with _$Rendition {
  const factory Rendition.text({
    required String id,
    required String itemId,
    required RenditionKind kind,

    /// El texto en sí, guardado en la base: es lo que se busca e indexa.
    required String content,
    required bool isPrimary,
    required DateTime createdAt,

    /// En una transcripción, cada palabra de lo dicho con el momento en que
    /// se dice, en orden —sin las marcas "[3:15]" de cada renglón— (F23):
    /// lo que permite resaltar la palabra que suena. Vacío si no se midió:
    /// un texto que no es una transcripción, o una transcripción hecha antes
    /// de F23. Se ubican en `content` por las palabras mismas, no por
    /// posición, así que siguen sirviendo después de "Quitar marcas de
    /// tiempo".
    @Default(<TimedWord>[]) List<TimedWord> wordTimings,
  }) = TextRendition;

  /// Contenido que vive como archivo: imagen, audio, PDF, la copia de una
  /// página.
  ///
  /// Fuera de la base a propósito. SQLite se vuelve lento si se le meten
  /// binarios grandes, y prácticamente ninguna consulta los necesita: la
  /// lista, la búsqueda y los filtros trabajan con texto y metadatos.
  const factory Rendition.file({
    required String id,
    required String itemId,
    required RenditionKind kind,

    /// Ruta relativa al directorio de datos de la app, nunca absoluta: en
    /// iOS y Android el contenedor de la app cambia de ruta entre
    /// instalaciones y actualizaciones, así que una ruta absoluta guardada
    /// hoy puede no existir mañana.
    required String relativePath,
    required bool isPrimary,
    required DateTime createdAt,
  }) = FileRendition;

  const Rendition._();

  /// La que se muestra por defecto cuando hay varias.
  bool get primary => switch (this) {
    TextRendition(:final isPrimary) => isPrimary,
    FileRendition(:final isPrimary) => isPrimary,
  };

  String get renditionId => switch (this) {
    TextRendition(:final id) => id,
    FileRendition(:final id) => id,
  };

  RenditionKind get renditionKind => switch (this) {
    TextRendition(:final kind) => kind,
    FileRendition(:final kind) => kind,
  };

  /// El texto buscable, o `null` si esta forma no tiene ninguno. Es lo que
  /// alimenta el índice de búsqueda.
  ///
  /// Una nota de bloques guarda JSON en `content` —claves como "type" o
  /// "checked" no son texto que alguien vaya a buscar—, así que se decodifica
  /// y se concatena solo el texto de cada bloque, igual que vería la persona
  /// que lo escribió.
  String? get searchableText => switch (this) {
    TextRendition(:final content, kind: RenditionKind.blocks) =>
      decodeContentBlocks(content).map((b) => b.text).join('\n'),
    TextRendition(:final content) => content,
    FileRendition() => null,
  };
}
