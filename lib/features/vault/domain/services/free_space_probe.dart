/// Cuánto espacio libre queda en el disco donde vive la bóveda.
///
/// Es una pieza aparte porque no todas las plataformas lo dicen y porque el
/// sistema real no se puede simular: los tests le ponen un doble con el espacio
/// que la prueba necesite.
// ignore: one_member_abstracts
abstract interface class FreeSpaceProbe {
  /// Los bytes libres del volumen donde está [path] (un archivo o un
  /// directorio), o `null` si no se pueden saber: la plataforma no lo dice, o
  /// preguntarlo falló. `null` no es «cero»: quien llama decide qué hace sin el
  /// dato.
  Future<int?> freeBytesAt(String path);
}
