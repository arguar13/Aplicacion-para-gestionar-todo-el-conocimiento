import 'package:meta/meta.dart';

/// Qué es un medio al que una tarjeta de Anki hace referencia.
enum AnkiMediaKind { image, audio, video }

/// Un medio (imagen, audio o video) que el texto de una tarjeta de Anki
/// referencia con `<img src="x.jpg">`, `[sound:x.mp3]`, `<audio>` o `<video>`.
///
/// Por ahora **no se importan**: la importación los cuenta, los saca del
/// texto de la tarjeta y avisa cuántos eran. El nombre queda por si más
/// adelante se trae el archivo del paquete (en el `.apkg`, cada medio es un
/// archivo numerado y la tabla `media` dice cómo se llama de verdad).
@immutable
class AnkiMediaRef {
  const AnkiMediaRef(this.name, this.kind);

  /// El nombre del archivo tal como lo escribe la tarjeta.
  final String name;
  final AnkiMediaKind kind;

  @override
  bool operator ==(Object other) =>
      other is AnkiMediaRef && other.name == name && other.kind == kind;

  @override
  int get hashCode => Object.hash(name, kind);

  @override
  String toString() => 'AnkiMediaRef($kind, $name)';
}
