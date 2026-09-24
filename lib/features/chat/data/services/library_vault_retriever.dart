import 'package:sinapsis/core/domain/entities/chat_source.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/chat/domain/services/vault_retriever.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';

/// [VaultRetriever] sobre la búsqueda de texto completo que ya tiene la
/// biblioteca (FTS5, ver la Fase 1 en docs/arquitectura.md).
///
/// No es búsqueda semántica de verdad —dos frases que dicen lo mismo con
/// palabras distintas no se encuentran entre sí—, pero es la que ya existe,
/// probada y sin ningún modelo de embeddings que descargar aparte. Ver la
/// decisión 20: si la calidad no alcanza, el camino de mejora es sumar
/// embeddings sin tocar esta interfaz, no reescribirla.
class LibraryVaultRetriever implements VaultRetriever {
  const LibraryVaultRetriever({required LibraryRepository library})
    : _library = library;

  final LibraryRepository _library;

  /// Cuánto del contenido de un elemento entra en la cita. Un fragmento, no
  /// el elemento entero: lo que se le pasa al modelo de lenguaje después
  /// tiene que caber en su ventana de contexto, y lo que se le muestra a la
  /// persona tiene que leerse de un vistazo.
  static const _excerptLength = 400;

  @override
  Future<List<ChatSource>> retrieve(
    String question, {
    int limit = 4,
    Set<String>? scopeIds,
  }) async {
    final terms = question
        .trim()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList();
    if (terms.isEmpty) return const [];

    // Una palabra por consulta, no la pregunta entera de una: `LibraryQuery`
    // arma sus términos con AND implícito (ver `buildSearchQuery`), que
    // tiene sentido para la barra de búsqueda —dos palabras sueltas, se
    // espera lo que tenga las dos— pero no acá. Exigir que las quince
    // palabras de "contame qué dice mi bóveda sobre religión" aparezcan
    // TODAS juntas en el mismo elemento no encuentra casi nunca nada; lo
    // único que importa es qué palabras de la pregunta aparecen en algún
    // lado, no que aparezcan todas a la vez.
    final itemsById = <String, KnowledgeItem>{};
    // Cuántas palabras DISTINTAS de la pregunta trajeron a este elemento.
    // Es lo primero que decide el orden: un elemento que toca dos temas de
    // la pregunta importa más que uno que solo toca uno, sin importar en
    // qué puesto haya salido cada búsqueda suelta.
    final matchedTerms = <String, int>{};
    // Desempate dentro del mismo número de palabras: la suma de en qué
    // puesto salió en cada búsqueda que sí lo encontró —temprano vale más
    // que tarde—, lo más parecido a "relevancia" que se puede armar sin
    // sumar un modelo de embeddings (ver la decisión 20).
    final rankScore = <String, int>{};

    for (final term in terms) {
      final result = await _library.list(
        LibraryQuery(
          searchText: term,
          sortBy: LibrarySort.relevance,
          limit: limit,
          ids: scopeIds,
        ),
      );
      result.match((_) {}, (items) {
        for (var rank = 0; rank < items.length; rank++) {
          final item = items[rank];
          itemsById[item.id] = item;
          matchedTerms[item.id] = (matchedTerms[item.id] ?? 0) + 1;
          rankScore[item.id] =
              (rankScore[item.id] ?? 0) + (items.length - rank);
        }
      });
    }

    final ranked = itemsById.values.toList()
      ..sort((a, b) {
        final byTermCount = (matchedTerms[b.id] ?? 0).compareTo(
          matchedTerms[a.id] ?? 0,
        );
        if (byTermCount != 0) return byTermCount;
        return (rankScore[b.id] ?? 0).compareTo(rankScore[a.id] ?? 0);
      });

    return ranked.take(limit).map(_toSource).toList();
  }

  ChatSource _toSource(KnowledgeItem item) {
    return ChatSource(
      itemId: item.id,
      itemTitle: item.title,
      excerpt: _excerptOf(item),
    );
  }

  String _excerptOf(KnowledgeItem item) {
    final text = item.searchableText.trim();
    if (text.isEmpty) return item.subtitle ?? '';
    if (text.length <= _excerptLength) return text;
    return '${text.substring(0, _excerptLength)}…';
  }
}
