import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_filter.dart';
import 'package:sinapsis/features/timeline/presentation/providers/timeline_providers.dart';

/// El único dueño del filtro de la línea de tiempo (F40).
void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  TimelineFilterNotifier notifier() =>
      container.read(timelineFilterProvider.notifier);
  TimelineFilter state() => container.read(timelineFilterProvider);

  const roma = TimelineScope.topic(spaceId: 'sp', label: 'Roma');
  const darwin = TimelineScope.document(itemId: 'it', label: 'Darwin');

  test('arranca sin filtros: Todo', () {
    expect(state(), const TimelineFilter());
  });

  test('fijar el filtro antes de que exista la pantalla no se pierde: quien '
      'abre la línea de tiempo desde otra pantalla lo pone y navega', () async {
    // Nadie mira el proveedor: con `autoDispose` se descartaría acá.
    notifier().focusOn(roma);
    await Future<void>.delayed(Duration.zero);
    await container.pump();

    expect(state().scope, roma);
  });

  group('focusOn (llegar desde otra pantalla)', () {
    test('deja SOLO ese recorte: borra la búsqueda y el panel de la vez '
        'anterior', () {
      notifier()
        ..search('césar')
        ..toggleSourceKind(SourceKind.webPage)
        ..toggleTagId('t')
        ..setScope(darwin);

      notifier().focusOn(roma);

      expect(state(), const TimelineFilter(scope: roma));
    });

    test('abrir otro recorte reemplaza al anterior', () {
      notifier()
        ..focusOn(roma)
        ..focusOn(darwin);

      expect(state().scope, darwin);
    });
  });

  group('setScope (la fila de chips)', () {
    test('cambia el recorte y conserva la búsqueda y el panel', () {
      notifier()
        ..search('césar')
        ..toggleSourceKind(SourceKind.webPage)
        ..setScope(roma);

      expect(state().scope, roma);
      expect(state().searchText, 'césar');
      expect(state().sourceKinds, {SourceKind.webPage});
    });

    test('un tema y un documento no se suman: el último reemplaza', () {
      notifier()
        ..setScope(roma)
        ..setScope(darwin);

      expect(state().scope, darwin);
      expect(state().query.spaceId, isNull);
      expect(state().query.ids, {'it'});
    });

    test('null es «Todo»', () {
      notifier()
        ..setScope(roma)
        ..setScope(null);

      expect(state().scope, isNull);
    });
  });

  group('búsqueda y panel', () {
    test('la búsqueda se recorta y, vacía, se quita', () {
      notifier().search('  césar  ');
      expect(state().searchText, 'césar');

      notifier().search('   ');
      expect(state().searchText, isNull);
    });

    test('un tipo o una etiqueta se prende y se apaga con el mismo toque', () {
      notifier()
        ..toggleSourceKind(SourceKind.webPage)
        ..toggleTagId('t');
      expect(state().sourceKinds, {SourceKind.webPage});
      expect(state().tagIds, {'t'});

      notifier()
        ..toggleSourceKind(SourceKind.webPage)
        ..toggleTagId('t');
      expect(state().sourceKinds, isEmpty);
      expect(state().tagIds, isEmpty);
    });

    test('quitar el panel deja el recorte y la búsqueda', () {
      notifier()
        ..setScope(roma)
        ..search('césar')
        ..toggleSourceKind(SourceKind.webPage)
        ..toggleTagId('t')
        ..clearPanel();

      expect(state(), const TimelineFilter(scope: roma, searchText: 'césar'));
    });

    test('quitar todo vuelve a Todo', () {
      notifier()
        ..setScope(roma)
        ..search('césar')
        ..toggleTagId('t')
        ..clear();

      expect(state(), const TimelineFilter());
    });
  });
}
