import 'package:freezed_annotation/freezed_annotation.dart';

part 'vault_merge_result.freezed.dart';

/// Lo que hizo una fusión de la copia de otra bóveda con esta (F11).
///
/// Cuenta lo que se escribió, no lo que se leyó: una fusión de la misma copia
/// por segunda vez da todo en cero.
@freezed
sealed class VaultMergeResult with _$VaultMergeResult {
  const factory VaultMergeResult({
    /// Elementos de la copia que esta bóveda no tenía.
    @Default(0) int itemsAdded,

    /// Elementos que esta bóveda ya tenía y que cambiaron, y cuántos campos.
    @Default(0) int itemsUpdated,
    @Default(0) int fieldsUpdated,

    /// Conflictos nuevos, guardados para que el usuario los revise: campos que
    /// se modificaron en las dos bóvedas sin que ninguna partiera de la otra, y
    /// textos distintos que entraron como otra forma.
    @Default(0) int conflictsRecorded,

    /// Espacios de la copia que esta bóveda no tenía.
    @Default(0) int spacesAdded,

    /// Formas de texto escritas —también las de los elementos nuevos— y textos
    /// de nota que pasaron a ser los de la copia.
    @Default(0) int renditionsAdded,
    @Default(0) int textsUpdated,

    /// Lo que se une por conjuntos: entra lo que acá no había.
    @Default(0) int relationsAdded,
    @Default(0) int highlightsAdded,
    @Default(0) int flashcardsAdded,

    /// Tarjetas que acá ya estaban y cuyo calendario pasó a ser el del repaso
    /// más reciente.
    @Default(0) int flashcardsUpdated,
    @Default(0) int reviewsAdded,
    @Default(0) int provenancesAdded,
    @Default(0) int conversationsAdded,
    @Default(0) int messagesAdded,

    /// El vocabulario: propiedades, valores, alias y lo asignado a cada
    /// elemento.
    @Default(0) int propertyDefinitionsAdded,
    @Default(0) int propertyValuesAdded,
    @Default(0) int propertyAliasesAdded,
    @Default(0) int propertyAssignmentsAdded,

    /// La jerarquía del vocabulario (F13): a cuántos valores se les puso el
    /// padre que traía la copia, y cuántas relaciones de padre no entraron
    /// porque el valor ya tenía otro, cerraban un ciclo o no cabían.
    @Default(0) int valueParentsAdopted,
    @Default(0) int valueParentsIgnored,

    /// Lo derivado que se rehízo: fuentes cuyos chunks se hicieron de nuevo, y
    /// las que no se pudieron fragmentar —su texto está entero y se reintenta—.
    @Default(0) int sourcesChunked,
    @Default(0) int sourcesPending,

    /// Archivos originales: los que faltaban y se copiaron —con cuánto pesan—,
    /// los que un elemento referencia y no están en ninguna de las dos, y los
    /// que están en las dos con distinto peso (se queda el de acá).
    @Default(0) int filesCopied,
    @Default(0) int filesCopiedBytes,
    @Default(0) int filesMissing,
    @Default(0) int filesDiffering,

    /// El rastro mínimo de la racha (F17, D6): triar la Bandeja, resolver
    /// algo en Vocabulario.
    @Default(0) int habitEventsAdded,
  }) = _VaultMergeResult;

  const VaultMergeResult._();

  /// Si la fusión no cambió nada.
  bool get changedNothing =>
      itemsAdded == 0 &&
      fieldsUpdated == 0 &&
      conflictsRecorded == 0 &&
      spacesAdded == 0 &&
      renditionsAdded == 0 &&
      textsUpdated == 0 &&
      relationsAdded == 0 &&
      highlightsAdded == 0 &&
      flashcardsAdded == 0 &&
      flashcardsUpdated == 0 &&
      reviewsAdded == 0 &&
      provenancesAdded == 0 &&
      conversationsAdded == 0 &&
      messagesAdded == 0 &&
      propertyDefinitionsAdded == 0 &&
      propertyValuesAdded == 0 &&
      propertyAliasesAdded == 0 &&
      propertyAssignmentsAdded == 0 &&
      valueParentsAdopted == 0 &&
      sourcesChunked == 0 &&
      filesCopied == 0 &&
      habitEventsAdded == 0;
}
