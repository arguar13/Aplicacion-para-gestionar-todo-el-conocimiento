import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_filter.dart';

/// El filtro de la línea de tiempo (F40) y la consulta de la biblioteca que
/// sale de él.
void main() {
  group('la consulta', () {
    test('sin nada puesto no restringe: se ve todo lo procesado (F41, paso '
        '6)', () {
      const filter = TimelineFilter();

      expect(filter.query, const LibraryQuery(scope: LibraryScope.processed));
      expect(filter.query.isFiltered, isFalse);
      expect(filter.query.isFiltered, isFalse);
      expect(filter.activeCount, 0);
    });

    test('un tema es el espacio de la consulta y nada más', () {
      const filter = TimelineFilter(
        scope: TimelineScope.topic(spaceId: 'sp', label: 'Roma'),
      );

      expect(
        filter.query,
        const LibraryQuery(spaceId: 'sp', scope: LibraryScope.processed),
      );
    });

    test('una rama del Atlas es el valor de la propiedad', () {
      const filter = TimelineFilter(
        scope: TimelineScope.branch(valueId: 'v', label: 'Imperio'),
      );

      expect(
        filter.query,
        const LibraryQuery(
          propertyValueIds: {'v'},
          scope: LibraryScope.processed,
        ),
      );
    });

    test('un documento limita la consulta a ese elemento (ids)', () {
      const filter = TimelineFilter(
        scope: TimelineScope.document(itemId: 'it', label: 'Darwin'),
      );

      expect(filter.query.ids, {'it'});
      expect(filter.query.spaceId, isNull);
      expect(filter.query.propertyValueIds, isEmpty);
    });

    test('la búsqueda y el panel se suman al recorte', () {
      const filter = TimelineFilter(
        scope: TimelineScope.topic(spaceId: 'sp', label: 'Roma'),
        searchText: 'césar',
        sourceKinds: {SourceKind.webPage},
        tagIds: {'t1', 't2'},
      );

      expect(
        filter.query,
        const LibraryQuery(
          spaceId: 'sp',
          searchText: 'césar',
          sourceKinds: {SourceKind.webPage},
          tagIds: {'t1', 't2'},
          scope: LibraryScope.processed,
        ),
      );
    });

    test('dos filtros iguales dan la misma consulta, el nombre del recorte no '
        'la cambia', () {
      const a = TimelineFilter(
        scope: TimelineScope.topic(spaceId: 'sp', label: 'Roma'),
      );
      const b = TimelineFilter(
        scope: TimelineScope.topic(spaceId: 'sp', label: 'Roma antigua'),
      );

      expect(a.query, b.query);
      expect(a, isNot(b));
    });
  });

  group('cuántos filtros hay', () {
    test('el panel cuenta tipos y etiquetas', () {
      const filter = TimelineFilter(
        sourceKinds: {SourceKind.webPage, SourceKind.manualNote},
        tagIds: {'t'},
      );

      expect(filter.panelCount, 3);
    });

    test('el total suma el recorte, la búsqueda y el panel', () {
      const filter = TimelineFilter(
        scope: TimelineScope.document(itemId: 'it', label: 'Darwin'),
        searchText: 'x',
        sourceKinds: {SourceKind.webPage},
      );

      expect(filter.activeCount, 3);
    });

    test('una búsqueda de puros espacios no es una búsqueda', () {
      const filter = TimelineFilter(searchText: '   ');

      expect(filter.hasSearchText, isFalse);
      expect(filter.activeCount, 0);
    });
  });

  group('el recorte', () {
    test('dos recortes son iguales si son del mismo tipo, id y nombre', () {
      expect(
        const TimelineScope.topic(spaceId: 'a', label: 'A'),
        const TimelineScope.topic(spaceId: 'a', label: 'A'),
      );
      expect(
        const TimelineScope.topic(spaceId: 'a', label: 'A'),
        isNot(const TimelineScope.document(itemId: 'a', label: 'A')),
      );
    });

    test('guarda su tipo, su id y su nombre', () {
      const scope = TimelineScope.branch(valueId: 'v', label: 'Imperio');

      expect(scope.kind, TimelineScopeKind.branch);
      expect(scope.id, 'v');
      expect(scope.label, 'Imperio');
    });
  });
}
