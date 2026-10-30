import 'package:freezed_annotation/freezed_annotation.dart';

part 'vault_merge_preview.freezed.dart';

/// Lo que pasaría si se fusionara una copia con esta bóveda, dicho ANTES de
/// tocar nada (F11).
///
/// Es una vista previa en seco: se calcula leyendo las dos bases, sin escribir
/// ninguna. Lo que muestra son las novedades que traería la copia —lo que esta
/// bóveda no tiene y los campos que la copia cambió con más derecho—; fusionar
/// nunca borra nada de lo que ya hay.
@freezed
sealed class VaultMergePreview with _$VaultMergePreview {
  const factory VaultMergePreview({
    /// Cuántos elementos trae la copia, vivos o en su papelera.
    required int incomingItems,

    /// De esos, los que esta bóveda no tiene, por su identificador: una fuente
    /// o una nota que es la misma en las dos tiene el mismo id, y no se
    /// duplica.
    required int newSources,
    required int newNotes,

    /// Los que las dos bóvedas tienen.
    required int commonItems,

    /// De esos, cuántos cambiarían y cuántos campos en total: los que la copia
    /// modificó partiendo de la versión de esta bóveda, o los que nadie había
    /// modificado acá. Los conflictos aparte: son campos modificados en las
    /// dos bóvedas a la vez, y se guardan para que el usuario los revise.
    @Default(0) int itemsToUpdate,
    @Default(0) int fieldsToUpdate,
    @Default(0) int conflicts,

    /// Formas de texto que la copia agrega a elementos que las dos tienen —
    /// también los textos distintos, que entran como otra forma—.
    @Default(0) int newRenditions,

    /// Lo que cuelga de los elementos y esta bóveda no tiene.
    @Default(0) int newRelations,
    @Default(0) int newHighlights,
    @Default(0) int newFlashcards,
    @Default(0) int newSpaces,
    @Default(0) int newPropertyValues,
    @Default(0) int newConversations,

    /// Lo resaltado para estudiar un documento (F36) y los hechos fechados que
    /// la línea de tiempo lee (F40), con la regla de la unión: las marcas que
    /// acá no están y los hechos que acá no hay, no repetidos por otro id.
    @Default(0) int newStudyMarks,
    @Default(0) int newDatedEvents,

    /// Las partes de documentos procesados (F41) que acá no están —páginas del
    /// texto, oraciones, notas, fragmentos—, con la regla de la unión. Un
    /// procesado nuevo se cuenta además en los elementos nuevos.
    @Default(0) int newProcessedParts,

    /// «Lo creado» de Estudiar (F43) que acá no está, con la regla de la unión.
    @Default(0) int newStudyCreations,

    /// Las notas en el texto (F45, mejora 19) que acá no están, con la regla
    /// de la unión.
    @Default(0) int newTextNotes,

    /// Archivos originales de la copia que esta bóveda no tiene, con cuánto
    /// pesan; y los que la copia dice tener y no trae.
    @Default(0) int newFiles,
    @Default(0) int newFilesBytes,
    @Default(0) int filesMissingInBackup,
  }) = _VaultMergePreview;

  const VaultMergePreview._();

  /// Los elementos que esta bóveda no tiene.
  int get newItems => newSources + newNotes;

  /// Si la copia no trae nada que esta bóveda no tenga.
  bool get hasNothingNew =>
      newItems == 0 &&
      fieldsToUpdate == 0 &&
      conflicts == 0 &&
      newRenditions == 0 &&
      newRelations == 0 &&
      newHighlights == 0 &&
      newFlashcards == 0 &&
      newSpaces == 0 &&
      newPropertyValues == 0 &&
      newConversations == 0 &&
      newStudyMarks == 0 &&
      newDatedEvents == 0 &&
      newProcessedParts == 0 &&
      newStudyCreations == 0 &&
      newTextNotes == 0 &&
      newFiles == 0;
}
