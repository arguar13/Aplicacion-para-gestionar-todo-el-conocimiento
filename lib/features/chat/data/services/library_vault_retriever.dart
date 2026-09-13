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
  Future<List<ChatSource>> retrieve(String question, {int limit = 4}) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty) return const [];

    final result = await _library.list(
      LibraryQuery(
        searchText: trimmed,
        sortBy: LibrarySort.relevance,
        limit: limit,
      ),
    );

    return result.match(
      (_) => const [],
      (items) => items.map(_toSource).toList(),
    );
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
