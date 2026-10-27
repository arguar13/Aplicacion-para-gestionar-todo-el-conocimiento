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

/// Qué parte de un texto se lee (F39): todo, o solo lo estudiado de él.
///
/// Cada una es una lista de pedazos con **sus posiciones en el texto
/// entero** —ver [ReadableDocument.scopes]—: lo que suena se resalta en su
/// lugar del texto, no en uno aparte.
enum ReadScope {
  /// Lo que se ve, de punta a punta.
  all,

  /// Las oraciones del resumen, en el orden del texto.
  summary,

  /// Las oraciones de la síntesis, en el orden del texto.
  synthesis,

  /// Las palabras clave, una tras otra, en el orden del texto.
  keywords,
}

/// Lo que una pantalla ofrece para leer en voz alta (F25): su texto, ya
/// partido en lo que se lee de una vez.
///
/// [segments] es lo que se lee con [ReadScope.all]. Un texto que se estudia
/// ofrece además, en [scopes], lo que se lee con cada capa de lo estudiado:
/// pedazos del mismo texto, con las mismas posiciones y el mismo
/// [ReadableSegment.sourceKey], así que lo que suena cae en su lugar del
/// texto entero. Una capa que se ofrece sin pedazos —todavía no hay
/// resumen— se ve en el reproductor, apagada.
@immutable
class ReadableDocument {
  const ReadableDocument({
    required this.id,
    required this.title,
    required this.segments,
    this.scopes = const {},
    this.ownAudio = false,
  });

  /// Qué es: lo mismo que se ofrece dos veces —la pantalla se reconstruyó—
  /// tiene el mismo [id], y el lector no vuelve a empezar.
  final String id;

  /// Lo que muestra el reproductor: el título del elemento, "Chat"...
  final String title;

  /// Lo que se lee con [ReadScope.all].
  final List<ReadableSegment> segments;

  /// Lo que se lee con cada capa de lo estudiado; nunca trae
  /// [ReadScope.all], que es [segments].
  final Map<ReadScope, List<ReadableSegment>> scopes;

  /// Si el texto ya suena en su propio audio —un audio, un video— (F23). El
  /// lector en voz alta no arranca por él: sería un segundo audio de lo
  /// mismo. Sin nada estudiado no lo ofrece; con algo estudiado, «Todo» se
  /// puede elegir, y se empieza por la primera capa con algo (F40, pedido
  /// del dueño: «Todo» estaba apagado en la transcripción de un audio).
  final bool ownAudio;

  /// Los pedazos que se leen con [scope]; ninguno si no se ofrece.
  List<ReadableSegment> segmentsOf(ReadScope scope) => switch (scope) {
    ReadScope.all when ownAudio && !_studiedAnything =>
      const <ReadableSegment>[],
    ReadScope.all => segments,
    _ => scopes[scope] ?? const <ReadableSegment>[],
  };

  /// Si hay algo que leer con [scope].
  bool offers(ReadScope scope) => segmentsOf(scope).isNotEmpty;

  /// Si ofrece elegir qué parte leer —un texto que se estudia—, haya o no
  /// algo estudiado todavía.
  bool get hasScopes => scopes.isNotEmpty;

  /// Si alguna capa de lo estudiado tiene algo.
  bool get _studiedAnything => scopes.values.any((s) => s.isNotEmpty);

  /// Con qué parte empieza a leer quien no eligió: todo, y si no hay —el
  /// texto está plegado— la primera capa estudiada que tenga algo. Con
  /// [ownAudio], siempre la primera capa estudiada con algo.
  ReadScope get defaultScope {
    for (final scope in ReadScope.values) {
      if (ownAudio && scope == ReadScope.all) continue;
      if (offers(scope)) return scope;
    }
    return ReadScope.all;
  }

  /// El mismo documento, con el texto que ya suena en su propio audio
  /// ([ownAudio]).
  ReadableDocument withOwnAudio() => ReadableDocument(
    id: id,
    title: title,
    segments: segments,
    scopes: scopes,
    ownAudio: true,
  );

  /// Con [scopes] en lugar de los que traía.
  ReadableDocument withScopes(Map<ReadScope, List<ReadableSegment>> scopes) =>
      ReadableDocument(
        id: id,
        title: title,
        segments: segments,
        scopes: scopes,
        ownAudio: ownAudio,
      );

  /// Si no hay nada que leer, con ninguna parte.
  bool get isEmpty =>
      ReadScope.values.every((scope) => segmentsOf(scope).isEmpty);

  @override
  bool operator ==(Object other) =>
      other is ReadableDocument &&
      other.id == id &&
      other.title == title &&
      other.ownAudio == ownAudio &&
      listEquals(other.segments, segments) &&
      _sameScopes(other.scopes, scopes);

  @override
  int get hashCode => Object.hash(
    id,
    title,
    ownAudio,
    Object.hashAll(segments),
    Object.hashAll([
      for (final scope
          in scopes.keys.toList()..sort((a, b) => a.index - b.index))
        Object.hash(scope, Object.hashAll(scopes[scope]!)),
    ]),
  );
}

bool _sameScopes(
  Map<ReadScope, List<ReadableSegment>> a,
  Map<ReadScope, List<ReadableSegment>> b,
) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final other = b[entry.key];
    if (other == null || !listEquals(entry.value, other)) return false;
  }
  return true;
}
