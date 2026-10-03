/// Si el dispositivo está enchufado (F27, decisión C): la pasada por la
/// biblioteca que ya existía corre solo así, para no gastar batería en horas
/// de modelo de lenguaje.
///
/// Detrás de una interfaz por lo mismo que `FreeSpaceProbe`: el plugin
/// necesita un sistema operativo de verdad, y las pruebas no lo tienen.
abstract interface class ChargingProbe {
  /// Si está enchufado ahora. `false` si no se puede saber: ante la duda, no
  /// se gasta batería.
  Future<bool> isCharging();

  /// Cada vez que se enchufa o se desenchufa.
  Stream<bool> watchCharging();
}
