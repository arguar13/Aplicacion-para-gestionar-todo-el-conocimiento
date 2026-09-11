import 'package:uuid/uuid.dart';

/// Quién inventa los identificadores.
///
/// Se abstrae por la misma razón que el reloj: un test que quiera comprobar
/// qué se guardó necesita saber con qué identificador buscarlo, y adivinar un
/// UUID aleatorio no es una opción.
// ignore: one_member_abstracts
abstract interface class IdGenerator {
  String next();
}

/// UUID versión 7.
///
/// La versión 7 y no la 4 porque lleva la marca de tiempo en los bits más
/// significativos: los identificadores quedan ordenados por momento de
/// creación, y una inserción nueva cae siempre al final del índice en vez de
/// dispersarse por todo el árbol. Con una biblioteca que solo crece, esa
/// diferencia se nota.
class UuidV7Generator implements IdGenerator {
  const UuidV7Generator([this._uuid = const Uuid()]);

  final Uuid _uuid;

  @override
  String next() => _uuid.v7();
}
