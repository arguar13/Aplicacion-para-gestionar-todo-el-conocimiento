import 'package:sinapsis/core/domain/entities/vocabulary_hierarchy.dart';

/// Por qué un valor no puede ir bajo un padre (F13).
enum VocabularyMoveProblem {
  /// El padre elegido es el propio valor o uno de sus descendientes.
  cycle,

  /// El valor, con todo lo que cuelga de él, pasaría de los cinco niveles.
  tooDeep,
}

/// El árbol de una categoría del vocabulario: quién es padre de quién.
///
/// Una función pura sobre pares (valor, padre), sin base ni pantalla: la usan
/// el repositorio para validar un movimiento antes de escribirlo, la pantalla
/// de Vocabulario para dibujar el árbol y el Atlas para contar en cascada. Un
/// solo lugar donde vive la regla de qué es un descendiente.
///
/// Es tolerante con lo que no debería pasar: un padre que no está en la lista
/// deja al valor como raíz, y un ciclo —que la base no admite— no cuelga el
/// recorrido.
class VocabularyTree {
  VocabularyTree(Iterable<({String id, String? parentId})> values) {
    final known = {for (final v in values) v.id};
    for (final v in values) {
      final parent = v.parentId;
      if (parent != null && parent != v.id && known.contains(parent)) {
        _parentOf[v.id] = parent;
        (_children[parent] ??= []).add(v.id);
      } else {
        _roots.add(v.id);
      }
    }
  }

  final Map<String, String> _parentOf = {};
  final Map<String, List<String>> _children = {};
  final List<String> _roots = [];

  /// Los valores sin padre, en el orden en que se dieron.
  List<String> get roots => List.unmodifiable(_roots);

  /// El padre de [id], o `null` si es una raíz o no está.
  String? parentOf(String id) => _parentOf[id];

  /// Los hijos directos de [id], en el orden en que se dieron.
  List<String> childrenOf(String id) =>
      List.unmodifiable(_children[id] ?? const <String>[]);

  /// Lo que cuelga de [id], sin contarlo, los padres antes que los hijos.
  List<String> descendantsOf(String id) {
    final found = <String>[];
    final seen = {id};
    var level = childrenOf(id);
    while (level.isNotEmpty) {
      final next = <String>[];
      for (final child in level) {
        if (!seen.add(child)) continue;
        found.add(child);
        next.addAll(_children[child] ?? const <String>[]);
      }
      level = next;
    }
    return found;
  }

  /// Los padres de [id], del más cercano a la raíz. Vacío para una raíz.
  List<String> ancestorsOf(String id) {
    final found = <String>[];
    final seen = {id};
    var current = _parentOf[id];
    while (current != null && seen.add(current)) {
      found.add(current);
      current = _parentOf[current];
    }
    return found;
  }

  /// Cuántos padres tiene [id] por encima: 0 para una raíz.
  int depthOf(String id) => ancestorsOf(id).length;

  /// Cuántos niveles hay DEBAJO de [id]: 0 si no tiene hijos.
  int heightOf(String id) {
    var height = 0;
    var level = childrenOf(id);
    final seen = {id};
    while (level.isNotEmpty) {
      height++;
      final next = <String>[];
      for (final child in level) {
        if (seen.add(child)) next.addAll(_children[child] ?? const <String>[]);
      }
      level = next;
    }
    return height;
  }

  /// Cuántos valores hay en la rama de [id], contándolo.
  int sizeOf(String id) => 1 + descendantsOf(id).length;

  /// Qué impide poner [id] —con todo lo que cuelga de él— bajo [newParentId],
  /// o `null` si se puede. `newParentId == null` es «hacerlo raíz», que
  /// siempre se puede.
  VocabularyMoveProblem? problemMoving(String id, String? newParentId) {
    if (newParentId == null) return null;
    if (newParentId == id || descendantsOf(id).contains(newParentId)) {
      return VocabularyMoveProblem.cycle;
    }
    final newDepth = depthOf(newParentId) + 1;
    if (newDepth + heightOf(id) > kVocabularyMaxDepth) {
      return VocabularyMoveProblem.tooDeep;
    }
    return null;
  }
}
