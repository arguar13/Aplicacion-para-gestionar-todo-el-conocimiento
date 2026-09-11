import 'package:sinapsis/core/util/id_generator.dart';

/// Identificadores predecibles: `id-0`, `id-1`, `id-2`...
///
/// Un UUID real es imposible de afirmar en un test —no se puede saber de
/// antemano qué va a salir— y comparar contra "algo no vacío" no prueba gran
/// cosa. Con identificadores en secuencia se puede comprobar exactamente qué
/// quedó apuntando a qué: que la forma de contenido referencie al elemento
/// que la contiene, y no a cualquier otro.
class FakeIdGenerator implements IdGenerator {
  FakeIdGenerator({this.prefix = 'id'});

  final String prefix;
  var _next = 0;

  /// Cuántos se pidieron. Sirve para comprobar que un adaptador no gasta
  /// identificadores de más.
  int get generated => _next;

  @override
  String next() => '$prefix-${_next++}';
}
