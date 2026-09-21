/// Qué clase de operación de mantenimiento del vocabulario se aplicó.
enum VocabularyOperationKind {
  merge,
  rename,
  delete,
  deleteCategory,
  addAlias,
  removeAlias,

  /// Mover un valor —con su rama— bajo otro padre, o a la raíz (F13).
  move,
}

/// Una operación de mantenimiento ya aplicada, con lo necesario para
/// deshacerla.
///
/// Es opaca a propósito: quien la recibe —la pantalla— solo la guarda y se la
/// devuelve al repositorio en `undo`. Lo que hace falta para revertirla
/// (filas, asignaciones, alias) es detalle de la capa de datos y no tiene por
/// qué filtrarse al dominio. Vive en memoria mientras dura la sesión: no se
/// persiste, así que cerrar la app la olvida.
///
/// Expone lo justo para que la interfaz arme un mensaje —"Se fusionaron 3
/// valores en «Roma»"— sin construir texto acá: los textos van localizados.
abstract interface class VocabularyOperation {
  VocabularyOperationKind get kind;

  /// Cuántos valores tocó: los fusionados, los borrados, 1 en el resto.
  int get valueCount;

  /// El texto que la describe: el valor que se conservó, el nombre nuevo, el
  /// alias.
  String get label;

  /// Cuántos elementos afectó.
  int get affectedItems;
}

/// Lo que va a pasar si se confirma una fusión: para mostrar "esto afectará a
/// N elementos" ANTES de hacerla.
/// Lo que movería poner un valor bajo un padre nuevo (F13), sin hacerlo.
class MovePreview {
  const MovePreview({required this.valueCount, required this.newDepth});

  /// Cuántos valores cambian de lugar: el que se mueve y toda su rama.
  final int valueCount;

  /// El nivel en el que queda el valor que se mueve: 0 si pasa a la raíz.
  final int newDepth;
}

class MergePreview {
  const MergePreview({required this.valueCount, required this.affectedItems});

  /// Cuántos valores se van a fusionar en el que se conserva.
  final int valueCount;

  /// Cuántos elementos distintos tienen alguno de esos valores.
  final int affectedItems;
}
