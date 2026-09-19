import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';

void main() {
  group('isFiltered', () {
    test('una consulta sin restricciones alcanza toda la biblioteca', () {
      expect(const LibraryQuery().isFiltered, isFalse);
    });

    test('el orden y la página no son filtros', () {
      const query = LibraryQuery(
        sortBy: LibrarySort.title,
        descending: false,
        limit: 10,
        offset: 20,
      );

      expect(query.isFiltered, isFalse);
    });

    test('una búsqueda de puros espacios no es un filtro', () {
      expect(const LibraryQuery(searchText: '   ').isFiltered, isFalse);
    });

    test('cada restricción lo vuelve un filtro', () {
      final restricted = [
        const LibraryQuery(searchText: 'roma'),
        const LibraryQuery(sourceKinds: {SourceKind.youtube}),
        const LibraryQuery(tagIds: {'t'}),
        const LibraryQuery(propertyValueIds: {'p'}),
        const LibraryQuery(spaceId: 's'),
        const LibraryQuery(processingStates: {ProcessingState.failed}),
      ];

      for (final query in restricted) {
        expect(query.isFiltered, isTrue, reason: '$query');
      }
    });
  });
}
