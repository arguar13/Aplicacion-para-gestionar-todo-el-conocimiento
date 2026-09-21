import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/map/presentation/providers/map_filter_provider.dart';

/// Los filtros del mapa (F14, D8): la misma consulta que entiende la
/// biblioteca, con lo justo para editarla desde el panel.
void main() {
  late ProviderContainer container;
  late MapFilterNotifier notifier;

  LibraryQuery current() => container.read(mapFilterProvider);

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
    // Vivo mientras dura la prueba: es `autoDispose`.
    container.listen(mapFilterProvider, (_, _) {});
    notifier = container.read(mapFilterProvider.notifier);
  });

  test('parte sin filtros', () {
    expect(current().isFiltered, isFalse);
    expect(activeMapFilters(current()), 0);
  });

  test('un tipo se pone y se saca al tocarlo otra vez', () {
    notifier.toggleSourceKind(SourceKind.document);
    expect(current().sourceKinds, {SourceKind.document});

    notifier.toggleSourceKind(SourceKind.youtube);
    expect(current().sourceKinds, {SourceKind.document, SourceKind.youtube});

    notifier.toggleSourceKind(SourceKind.document);
    expect(current().sourceKinds, {SourceKind.youtube});
  });

  test('una etiqueta se pone y se saca igual', () {
    notifier
      ..toggleTagId('t1')
      ..toggleTagId('t2')
      ..toggleTagId('t1');

    expect(current().tagIds, {'t2'});
  });

  test('la búsqueda se recorta, y un texto vacío la quita', () {
    notifier.search('  roma  ');
    expect(current().searchText, 'roma');

    notifier.search('   ');
    expect(current().searchText, isNull);
    expect(current().hasSearchText, isFalse);
  });

  test('cuenta cada tipo, cada etiqueta y la búsqueda', () {
    notifier
      ..toggleSourceKind(SourceKind.document)
      ..toggleSourceKind(SourceKind.webPage)
      ..toggleTagId('t1')
      ..search('roma');

    expect(activeMapFilters(current()), 4);
  });

  test('quitar todo lo deja como al principio', () {
    notifier
      ..toggleSourceKind(SourceKind.document)
      ..search('roma')
      ..clear();

    expect(current().isFiltered, isFalse);
    expect(activeMapFilters(current()), 0);
  });
}
