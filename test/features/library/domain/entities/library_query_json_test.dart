import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/domain/entities/library_query_json.dart';

void main() {
  test('ida y vuelta: lo que entra sale igual', () {
    const query = LibraryQuery(
      searchText: 'paradigma',
      sourceKinds: {SourceKind.webPage, SourceKind.youtube},
      tagIds: {'t1'},
      propertyValueIds: {'v1', 'v2'},
      spaceId: 'sp1',
      processingStates: {ProcessingState.ready, ProcessingState.pending},
      sortBy: LibrarySort.title,
      descending: false,
    );

    expect(libraryQueryFromJson(libraryQueryToJson(query)), query);
  });

  test('una consulta vacía va y vuelve vacía', () {
    const query = LibraryQuery();

    expect(libraryQueryFromJson(libraryQueryToJson(query)), query);
  });

  test('ids, límite y página no se guardan', () {
    const query = LibraryQuery(ids: {'a'}, limit: 10, offset: 5);

    final json = libraryQueryToJson(query);

    expect(json.containsKey('ids'), isFalse);
    expect(json.containsKey('limit'), isFalse);
    expect(json.containsKey('offset'), isFalse);
  });

  test('un valor que ya no existe se ignora, sin fallar', () {
    final json = libraryQueryToJson(const LibraryQuery())
      ..['sourceKinds'] = ['unaClaseQueYaNoExiste']
      ..['sortBy'] = 'algoQueYaNoExiste';

    final query = libraryQueryFromJson(json);

    expect(query.sourceKinds, isEmpty);
    expect(query.sortBy, LibrarySort.capturedAt);
  });

  test('un json vacío o incompleto no falla', () {
    expect(libraryQueryFromJson(const {}), const LibraryQuery());
  });
}
