import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';

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

/// Un lugar de un texto en pantalla: el texto ([ReadableSegment.sourceKey]) y
/// una posición en él, tal cual se guarda.
typedef ReadablePlace = ({String sourceKey, int offset});

/// El audio ya generado de lo que se lee (F47, paso 6b): un podcast —o, en el
/// paso 5, el audio descargado de un documento—. Con él, el lector no le pide
/// nada a la voz: hace sonar el archivo, con su tiempo real, y resalta el
/// pedazo que suena por dónde empieza cada uno.
@immutable
class RecordedSpeech {
  const RecordedSpeech({
    required this.path,
    required this.duration,
    required this.starts,
    this.voices = const [],
  });

  /// La ruta del archivo en el teléfono.
  final String path;

  final Duration duration;

  /// Dónde empieza cada pedazo de `ReadableDocument.segments`, en orden.
  final List<Duration> starts;

  /// La voz que dice cada pedazo —para la cara del reproductor y la
  /// tarjeta—, en el mismo orden; vacía si no se sabe.
  final List<NarrationVoice?> voices;

  /// El pedazo que suena en [at]: el último que empezó.
  int segmentAt(Duration at) {
    var low = 0;
    var high = starts.length - 1;
    var found = 0;
    while (low <= high) {
      final middle = (low + high) >> 1;
      if (starts[middle] <= at) {
        found = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return found;
  }

  /// Dónde empieza el pedazo [index] —antes del primero, el principio—.
  Duration startOf(int index) {
    if (starts.isEmpty || index <= 0) return Duration.zero;
    return starts[index.clamp(0, starts.length - 1)];
  }

  /// La voz del pedazo [index], si se sabe.
  NarrationVoice? voiceAt(int index) =>
      index >= 0 && index < voices.length ? voices[index] : null;

  @override
  bool operator ==(Object other) =>
      other is RecordedSpeech &&
      other.path == path &&
      other.duration == duration &&
      listEquals(other.starts, starts) &&
      listEquals(other.voices, voices);

  @override
  int get hashCode => Object.hash(
    path,
    duration,
    Object.hashAll(starts),
    Object.hashAll(voices),
  );
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
    this.startAt,
    this.location,
    this.recording,
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

  /// Por dónde va la vista de la pantalla que lo ofrece, o `null` si se lee
  /// desde el principio: un libro abierto en la página 300 empieza a leer
  /// ahí, no en la portada. Se pregunta en el momento de empezar —ver
  /// [startIndexOf]—, porque la vista se mueve sin que el documento cambie:
  /// es una función, y no un lugar fijo. Que sea la misma —el mismo método
  /// del mismo objeto— es parte de ser el mismo documento.
  final ReadablePlace? Function()? startAt;

  /// La dirección de la pantalla que lo ofrece —la del router, la de
  /// arriba de todo cuando se ofrece—, o `null` si no se sabe: adonde se
  /// vuelve al tocar la tarjeta de lo que suena y «Seguir escuchando»
  /// (F47, pasos 1, 2b y 7a). La pone `ReadableRegion` al ofrecerlo.
  ///
  /// Una pantalla que se abre encima sin una ruta propia —un visor que se
  /// empuja con `Navigator.push`— dice la de la pantalla de abajo: se
  /// vuelve ahí, de donde se lo abrió.
  final String? location;

  /// Su audio ya generado, si tiene uno (F47, paso 6b): lo que suena con
  /// [ReadScope.all], en lugar de la voz. Uno por pedazo de [segments].
  final RecordedSpeech? recording;

  /// Desde qué pedazo de [scope] empieza a leer quien no eligió: el primero
  /// que termina después del lugar de [startAt] en su texto. Sin [startAt],
  /// o si ya no queda ninguno después —la vista está en la última página y
  /// el resumen terminó antes—, el primero.
  int startIndexOf(ReadScope scope) {
    final place = startAt?.call();
    if (place == null) return 0;
    final segments = segmentsOf(scope);
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      if (segment.sourceKey == place.sourceKey && segment.end > place.offset) {
        return i;
      }
    }
    return 0;
  }

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
    startAt: startAt,
    location: location,
    recording: recording,
  );

  /// Con [scopes] en lugar de los que traía.
  ReadableDocument withScopes(Map<ReadScope, List<ReadableSegment>> scopes) =>
      ReadableDocument(
        id: id,
        title: title,
        segments: segments,
        scopes: scopes,
        ownAudio: ownAudio,
        startAt: startAt,
        location: location,
        recording: recording,
      );

  /// Con [startAt] en lugar del que traía.
  ReadableDocument withStartAt(ReadablePlace? Function()? startAt) =>
      ReadableDocument(
        id: id,
        title: title,
        segments: segments,
        scopes: scopes,
        ownAudio: ownAudio,
        startAt: startAt,
        location: location,
        recording: recording,
      );

  /// Con [location] en lugar de la que traía.
  ReadableDocument withLocation(String? location) => ReadableDocument(
    id: id,
    title: title,
    segments: segments,
    scopes: scopes,
    ownAudio: ownAudio,
    startAt: startAt,
    location: location,
    recording: recording,
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
      other.startAt == startAt &&
      other.location == location &&
      other.recording == recording &&
      listEquals(other.segments, segments) &&
      _sameScopes(other.scopes, scopes);

  @override
  int get hashCode => Object.hash(
    id,
    title,
    ownAudio,
    startAt,
    location,
    recording,
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
