import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/features/chat/domain/services/chat_passages.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/notebooks/domain/entities/notebook.dart';

/// Desde cuántos elementos un tema o una etiqueta da para un cuaderno
/// sugerido (F30): con menos, el cuaderno es casi el elemento.
const kNotebookSuggestionMinItems = 3;

/// Cuántos cuadernos se sugieren, como mucho, a la vez: los de más elementos.
/// Un árbol de etiquetas puede tener miles de ramas.
const kMaxNotebookSuggestions = 8;

/// Cuántos títulos de ejemplo de cada sugerencia ve la IA para nombrarla.
const kNotebookSuggestionSampleTitles = 3;

/// De dónde sale un cuaderno sugerido: un tema (`Space`) o una etiqueta (un
/// valor de la categoría de sistema, con su árbol).
enum NotebookTopicKind { space, tag }

/// Un tema o una etiqueta, con cuántos elementos vivos tiene —una etiqueta,
/// contando lo de todas sus ramas, como la cuenta la Biblioteca—.
@immutable
class NotebookTopic {
  const NotebookTopic({
    required this.kind,
    required this.id,
    required this.name,
    required this.itemCount,
    this.parentId,
  });

  final NotebookTopicKind kind;
  final String id;
  final String name;
  final int itemCount;

  /// La etiqueta de arriba en el árbol; `null` en una raíz o en un tema.
  final String? parentId;

  @override
  bool operator ==(Object other) =>
      other is NotebookTopic &&
      other.kind == kind &&
      other.id == id &&
      other.name == name &&
      other.itemCount == itemCount &&
      other.parentId == parentId;

  @override
  int get hashCode => Object.hash(kind, id, name, itemCount, parentId);
}

/// Un cuaderno que se puede crear desde un tema o una etiqueta (F30): uno
/// **por consulta** ([query]), que se mantiene al día solo —lo que entra al
/// tema o recibe la etiqueta, aparece—.
@immutable
class NotebookSuggestion {
  const NotebookSuggestion({required this.topic});

  final NotebookTopic topic;

  /// Lo que identifica a la sugerencia entre aperturas: para recordar que la
  /// persona dijo «ahora no».
  String get key => '${topic.kind.name}:${topic.id}';

  /// La consulta del cuaderno: el tema, o la etiqueta con sus ramas.
  LibraryQuery get query => switch (topic.kind) {
    NotebookTopicKind.space => LibraryQuery(spaceId: topic.id),
    NotebookTopicKind.tag => LibraryQuery(tagIds: {topic.id}),
  };

  @override
  bool operator ==(Object other) =>
      other is NotebookSuggestion && other.topic == topic;

  @override
  int get hashCode => topic.hashCode;
}

/// Los cuadernos que vale la pena sugerir (F30), de los de más elementos a
/// los de menos, como mucho [max]:
///
/// - Con al menos [minItems] elementos.
/// - Una etiqueta que tiene exactamente los mismos elementos que la de
///   arriba no suma nada: sería el mismo cuaderno con otro nombre.
/// - Sin duplicar los que ya existen: ni uno por consulta que ya pide ese
///   tema o esa etiqueta, ni uno —de cualquier modo— con el mismo nombre.
/// - Sin los que la persona descartó ([dismissed], por
///   [NotebookSuggestion.key]).
/// - Un tema y una etiqueta con el mismo nombre dan un solo cuaderno, el de
///   más elementos.
List<NotebookSuggestion> suggestNotebooks({
  required List<NotebookTopic> topics,
  required List<Notebook> existing,
  Set<String> dismissed = const {},
  int minItems = kNotebookSuggestionMinItems,
  int max = kMaxNotebookSuggestions,
}) {
  final countOf = {
    for (final topic in topics)
      if (topic.kind == NotebookTopicKind.tag) topic.id: topic.itemCount,
  };
  final names = {for (final n in existing) foldForSearch(n.name.trim())};
  final queries = {
    for (final n in existing)
      if (n.mode == NotebookMode.query && n.query != null) _plain(n.query!),
  };

  final suggestions =
      [
        for (final topic in topics)
          if (NotebookSuggestion(topic: topic) case final suggestion
              when topic.itemCount >= minItems &&
                  !(topic.parentId != null &&
                      countOf[topic.parentId] == topic.itemCount) &&
                  !names.contains(foldForSearch(topic.name.trim())) &&
                  !queries.contains(_plain(suggestion.query)) &&
                  !dismissed.contains(suggestion.key))
            suggestion,
      ]..sort((a, b) {
        final byCount = b.topic.itemCount.compareTo(a.topic.itemCount);
        if (byCount != 0) return byCount;
        final byKind = a.topic.kind.index.compareTo(b.topic.kind.index);
        if (byKind != 0) return byKind;
        return a.topic.name.toLowerCase().compareTo(b.topic.name.toLowerCase());
      });
  final seenNames = <String>{};
  return [
    for (final suggestion in suggestions)
      if (seenNames.add(foldForSearch(suggestion.topic.name.trim())))
        suggestion,
  ].take(max).toList();
}

/// De dónde salen los cuadernos sugeridos (F30): los temas y las etiquetas
/// con cuántos elementos vivos tiene cada uno.
abstract interface class NotebookTopicReader {
  /// Los temas y las etiquetas con al menos un elemento, actualizándose solos
  /// cuando algo entra, sale o cambia de tema o de etiqueta. Una etiqueta
  /// cuenta lo de todas sus ramas, como la cuenta la Biblioteca al filtrar.
  Stream<List<NotebookTopic>> watchTopics();

  /// Hasta [limit] títulos de lo más reciente de [suggestion]: lo que la IA
  /// ve para nombrar el cuaderno.
  Future<List<String>> sampleTitles(
    NotebookSuggestion suggestion, {
    int limit = kNotebookSuggestionSampleTitles,
  });
}

/// [query] sin lo que no cambia qué elementos trae: el orden y la página.
LibraryQuery _plain(LibraryQuery query) => query.copyWith(
  sortBy: LibrarySort.capturedAt,
  descending: true,
  limit: null,
  offset: 0,
);

/// Lo que se le muestra a la IA de una sugerencia para que la nombre.
typedef NotebookNamingInput = ({
  String topic,
  int itemCount,
  List<String> titles,
});

/// El nombre y la línea que la IA propone para un cuaderno sugerido.
typedef NotebookNaming = ({String name, String? description});

/// Le pide a la IA un nombre —y, si aporta, una línea que diga qué reúne—
/// para cuadernos sugeridos (F30).
// ignore: one_member_abstracts
abstract interface class NotebookNamer {
  /// Lo propuesto para cada uno de [inputs], por su posición; los que la IA
  /// no nombró —o no se pudo leer— no están.
  Future<Map<int, NotebookNaming>> nameNotebooks(
    List<NotebookNamingInput> inputs,
  );
}

/// Cuántos nombra la IA por pedido.
const kNotebookNamingBatch = 5;

/// Lee las líneas `CUADERNO: <número> | <nombre> | <descripción>` (F30): los
/// números, desde 0, de los que están en la lista. Un nombre vacío o de más
/// de 60 caracteres no se toma; la descripción es opcional y se descarta si
/// pasa de 160.
Map<int, NotebookNaming> parseNotebookNames(String text, {required int count}) {
  final found = <int, NotebookNaming>{};
  final line = RegExp(r'^CUADERNO\s*:\s*(\d+)\s*\|(.*)$', caseSensitive: false);
  for (final raw in text.split('\n')) {
    final match = line.firstMatch(raw.replaceAll('*', '').trim());
    if (match == null) continue;
    final index = int.parse(match.group(1)!) - 1;
    if (index < 0 || index >= count || found.containsKey(index)) continue;
    final parts = match.group(2)!.split('|');
    final name = _clean(parts.first);
    if (name.isEmpty || name.length > 60) continue;
    final description = parts.length > 1
        ? _clean(parts.sublist(1).join('|'))
        : '';
    found[index] = (
      name: name,
      description: description.isEmpty || description.length > 160
          ? null
          : description,
    );
  }
  return found;
}

/// Sin comillas ni espacios de más alrededor.
String _clean(String text) =>
    text.trim().replaceAll(RegExp(r'^["«“]+|["»”]+$'), '').trim();
