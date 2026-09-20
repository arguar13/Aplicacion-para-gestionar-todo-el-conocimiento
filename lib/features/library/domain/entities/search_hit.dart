import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/library/domain/entities/search_citation.dart';

/// Un resultado de la búsqueda: el elemento, y DÓNDE está lo que se encontró.
///
/// [citation] es `null` cuando no hay dónde señalar: no se buscó texto, el
/// elemento coincide solo por su título o su subtítulo, o su texto es una nota,
/// que no se fragmenta ni tiene minuto ni página.
class SearchHit {
  const SearchHit({required this.item, this.citation});

  final KnowledgeItem item;
  final SearchCitation? citation;
}
