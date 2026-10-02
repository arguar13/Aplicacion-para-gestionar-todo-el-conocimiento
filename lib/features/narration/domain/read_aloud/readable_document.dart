import 'package:flutter/foundation.dart';

/// Un pedazo de lo que el lector flotante lee de una vez (F25): una línea
/// del texto —o, si es muy larga, una oración—, con **dónde está en
/// pantalla**: en qué texto ([sourceKey]) y entre qué posiciones de ese
/// texto, tal cual se guarda ([start], [end]). Es lo que se resalta en
/// amarillo mientras se lee.
///
/// [spoken] es lo que se le dice al motor de voz: el mismo pedazo sin lo que
/// no se pronuncia —las marcas "[3:15]" de una transcripción, los símbolos
/// de formato—. Los saltos de ±10 s y el avance se cuentan sobre [spoken].
@immutable
class ReadableSegment {
  const ReadableSegment({
    required this.sourceKey,
    required this.start,
    required this.end,
    required this.spoken,
  });

  /// Qué texto en pantalla: lo que cada pantalla usa para preguntar si lo
  /// que se está leyendo es suyo —ver `readAloudHighlightProvider`—. Por
  /// ejemplo, el identificador de la forma de texto de un elemento.
  final String sourceKey;

  /// `[start, end)` en el texto de [sourceKey].
  final int start;
  final int end;

  final String spoken;

  @override
  bool operator ==(Object other) =>
      other is ReadableSegment &&
      other.sourceKey == sourceKey &&
      other.start == start &&
      other.end == end &&
      other.spoken == spoken;

  @override
  int get hashCode => Object.hash(sourceKey, start, end, spoken);

  @override
  String toString() => 'ReadableSegment($sourceKey, $start-$end, "$spoken")';
}

/// Lo que una pantalla ofrece para leer en voz alta (F25): su texto, ya
/// partido en lo que se lee de una vez.
@immutable
class ReadableDocument {
  const ReadableDocument({
    required this.id,
    required this.title,
    required this.segments,
  });

  /// Qué es: lo mismo que se ofrece dos veces —la pantalla se reconstruyó—
  /// tiene el mismo [id], y el lector no vuelve a empezar.
  final String id;

  /// Lo que muestra el reproductor: el título del elemento, "Chat"...
  final String title;

  final List<ReadableSegment> segments;

  bool get isEmpty => segments.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is ReadableDocument &&
      other.id == id &&
      other.title == title &&
      listEquals(other.segments, segments);

  @override
  int get hashCode => Object.hash(id, title, Object.hashAll(segments));
}
