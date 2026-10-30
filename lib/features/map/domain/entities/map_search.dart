import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';

/// Cuántos resultados da la búsqueda del mapa, como mucho.
const kMapSearchResults = 20;

/// Qué se encontró en el mapa.
enum MapSearchKind {
  /// Un tema: se vuela hasta él en el nivel de los temas.
  topic,

  /// Un documento: se vuela hasta él en el nivel de los documentos, dentro de
  /// [MapSearchEntry.topicValueId] —o de la burbuja «Sin tema» si no tiene—.
  document,
}

/// Algo del mapa que se puede buscar, con su lugar (F44): en qué comunidad y en
/// qué tema está, para volar hasta él sin preguntarle a la base.
///
/// Es también como el motor nombra un documento en todo lo demás que sabe —lo
/// nuevo, la burbuja «Sin tema»—: siempre con su lugar.
class MapSearchEntry {
  const MapSearchEntry({
    required this.kind,
    required this.id,
    required this.label,
    required this.key,
    this.communityId,
    this.topicValueId,
    this.valueIds = const [],
    this.isNote = false,
    this.size = 0,
    this.createdAt,
  });

  final MapSearchKind kind;

  /// El valor del tema o el identificador del documento.
  final String id;

  /// El nombre del tema o el título del documento, como se muestra.
  final String label;

  /// [label] sin acentos ni mayúsculas (`normalizeVocabularyLabel`): contra
  /// esto se busca.
  final String key;

  /// La identidad de la comunidad donde está, o `null` en un documento sin
  /// tema.
  final int? communityId;

  /// El tema donde está: el propio, en un tema; en un documento, el de sus
  /// temas por el que se llega a él (`placeDocument`), o `null` si no tiene
  /// ninguno —entonces está en la burbuja «Sin tema»—.
  final String? topicValueId;

  /// Todos los temas de un documento; vacío en un tema.
  final List<String> valueIds;

  /// Si el documento es una nota; si no, es una fuente.
  final bool isNote;

  /// Cuántos documentos tiene un tema asignados directamente; 0 en un
  /// documento.
  final int size;

  /// Cuándo se procesó el documento, si se sabe.
  final DateTime? createdAt;

  /// Si es un documento sin ningún tema: vive en la burbuja «Sin tema».
  bool get isUnthemed => kind == MapSearchKind.document && topicValueId == null;
}

/// El índice de búsqueda del mapa (F44): todos sus temas y documentos con su
/// lugar.
///
/// Se arma en el isolate del cálculo y busca en memoria, sin la base: buscar
/// mientras se escribe no cuesta una consulta por letra.
class MapSearchIndex {
  const MapSearchIndex({
    required this.entries,
    required Map<String, int> topicAt,
    required Map<String, int> documentAt,
  }) : _topicAt = topicAt,
       _documentAt = documentAt;

  const MapSearchIndex.empty()
    : entries = const [],
      _topicAt = const {},
      _documentAt = const {};

  /// Los temas por nombre y después los documentos por título, sin acentos ni
  /// mayúsculas.
  final List<MapSearchEntry> entries;

  final Map<String, int> _topicAt;
  final Map<String, int> _documentAt;

  /// El tema con ese valor, o `null` si no está en el mapa.
  MapSearchEntry? topic(String valueId) {
    final at = _topicAt[valueId];
    return at == null ? null : entries[at];
  }

  /// El documento con ese identificador, o `null` si no está en el mapa.
  MapSearchEntry? document(String itemId) {
    final at = _documentAt[itemId];
    return at == null ? null : entries[at];
  }

  /// Lo que coincide con [query], lo que mejor coincide primero, como mucho
  /// [limit].
  ///
  /// Sin distinguir acentos ni mayúsculas. Primero lo que se llama igual,
  /// después lo que empieza así, lo que tiene una palabra que empieza así, lo
  /// que lo contiene y, con varias palabras, lo que las tiene todas en
  /// cualquier orden. A igual coincidencia, los temas antes que los
  /// documentos; los temas más grandes y los documentos más nuevos primero, y
  /// al final por nombre. Recorre el índice una vez.
  List<MapSearchEntry> search(String query, {int limit = kMapSearchResults}) {
    final wanted = normalizeVocabularyLabel(query);
    if (wanted.isEmpty || limit <= 0) return const [];
    final words = wanted.split(' ');

    final hits = <(int, int)>[];
    for (var i = 0; i < entries.length; i++) {
      final rank = _rank(entries[i].key, wanted, words);
      if (rank >= 0) hits.add((rank, i));
    }
    hits.sort((x, y) {
      final byRank = x.$1.compareTo(y.$1);
      if (byRank != 0) return byRank;
      final a = entries[x.$2];
      final b = entries[y.$2];
      final byKind = a.kind.index.compareTo(b.kind.index);
      if (byKind != 0) return byKind;
      final bySize = b.size.compareTo(a.size);
      if (bySize != 0) return bySize;
      final byDate = _compareNewestFirst(a.createdAt, b.createdAt);
      if (byDate != 0) return byDate;
      // El índice ya está por nombre: la posición desempata igual.
      return x.$2.compareTo(y.$2);
    });
    return [for (final (_, i) in hits.take(limit)) entries[i]];
  }
}

/// Cuán bien coincide [key] con [wanted]: 0 es lo mejor; -1, que no coincide.
int _rank(String key, String wanted, List<String> words) {
  if (key == wanted) return 0;
  if (key.startsWith(wanted)) return 1;
  if (key.contains(' $wanted')) return 2;
  if (key.contains(wanted)) return 3;
  if (words.length > 1 && words.every(key.contains)) return 4;
  return -1;
}

/// Lo más nuevo primero; lo que no tiene fecha, al final.
int _compareNewestFirst(DateTime? a, DateTime? b) {
  if (a == null || b == null) {
    return a == null ? (b == null ? 0 : 1) : -1;
  }
  return b.compareTo(a);
}
