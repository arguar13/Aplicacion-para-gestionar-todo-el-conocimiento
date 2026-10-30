import 'dart:typed_data';

/// Lo que el lienzo del Mapa ofrece para exportarse (F14, D7; F44, paso 2): su
/// dibujo como imagen y como SVG, y qué es para nombrar el archivo.
///
/// La pantalla se lo pasa al lienzo y el lienzo lo llena cuando ya tiene algo
/// que dibujar; la pantalla lo consulta al exportar. Así la pantalla no sabe
/// cómo se dibuja cada disposición, y lo que no se exporta —el Resumen, o el
/// lienzo visto como lista— no lo llena.
class MapExportHandle {
  /// El dibujo como PNG, o `null` si no hay nada dibujado todavía.
  Future<Uint8List?> Function()? png;

  /// El dibujo como documento SVG.
  String Function()? svg;

  /// Qué se dibuja ahora, para el nombre del archivo: la disposición —`red`,
  /// `radial` o `arbol`— y si son los documentos vinculados entre sí, que no
  /// dependen de lo que se agrupa.
  ({String arrangement, bool links}) Function()? subject;

  /// Si la vista ya se puede exportar.
  bool get available => png != null && svg != null;
}
