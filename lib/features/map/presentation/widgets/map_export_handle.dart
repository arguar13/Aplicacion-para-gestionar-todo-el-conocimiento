import 'dart:typed_data';

/// Lo que una vista del mapa ofrece para exportarse (F14, D7): su dibujo como
/// imagen y como SVG.
///
/// La pantalla se lo pasa a la vista y la vista lo llena cuando ya tiene algo
/// que dibujar; la pantalla lo consulta al exportar. Así la pantalla no sabe
/// cómo se dibuja cada vista, y una vista que no se exporta —el tablero— no lo
/// llena.
class MapExportHandle {
  /// El dibujo como PNG, o `null` si no hay nada dibujado todavía.
  Future<Uint8List?> Function()? png;

  /// El dibujo como documento SVG.
  String Function()? svg;

  /// Si la vista ya se puede exportar.
  bool get available => png != null && svg != null;
}
