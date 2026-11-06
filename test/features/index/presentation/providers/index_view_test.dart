import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/features/index/domain/entities/index_tree.dart';
import 'package:sinapsis/features/index/presentation/providers/index_arrivals.dart';
import 'package:sinapsis/features/index/presentation/providers/index_view.dart';

import '../../../../support/fake_index_repository.dart';

/// Lo que se está mirando del Índice (F46, paso 3) y lo que llegó mientras
/// tanto.
void main() {
  group('lo que se mira', () {
    Future<IndexViewController> controller([
      Map<String, Object> stored = const {},
    ]) async {
      SharedPreferences.setMockInitialValues(stored);
      return IndexViewController(await SharedPreferences.getInstance());
    }

    test('de entrada: por tema, de la A a la Z, tres niveles como en Word, '
        'sin numerar, sin buscar y con todo plegado menos los temas', () async {
      final view = (await controller()).state;

      expect(view.arrangement, IndexArrangement.byTopic);
      expect(view.order, IndexDocumentOrder.title);
      expect(view.depth, IndexDepth.three);
      expect(view.numbered, isFalse);
      expect(view.searching, isFalse);
      expect(view.foldedTopics, isEmpty);
      expect(view.openDocuments, isEmpty);
    });

    test('recuerda cómo se arma —no lo desplegado ni lo buscado— para la '
        'próxima vez', () async {
      final first = await controller();
      first
        ..arrange(IndexArrangement.byDocument)
        ..sortBy(IndexDocumentOrder.recent)
        ..showDepth(IndexDepth.all)
        ..toggleNumbering()
        ..toggleDocument('a')
        ..search('nicea');

      final prefs = await SharedPreferences.getInstance();
      final again = IndexViewController(prefs).state;

      expect(again.arrangement, IndexArrangement.byDocument);
      expect(again.order, IndexDocumentOrder.recent);
      expect(again.depth, IndexDepth.all);
      expect(again.numbered, isTrue);
      expect(again.openDocuments, isEmpty);
      expect(again.query, isEmpty);
    });

    test('cada elección se recuerda sola, sin esperar a otra', () async {
      final elections = <(String, void Function(IndexViewController))>[
        ('la forma', (c) => c.arrange(IndexArrangement.byDocument)),
        ('el orden', (c) => c.sortBy(IndexDocumentOrder.recent)),
        ('los niveles', (c) => c.showDepth(IndexDepth.one)),
        ('la numeración', (c) => c.toggleNumbering()),
      ];
      for (final (what, choose) in elections) {
        choose(await controller());
        final again = IndexViewController(
          await SharedPreferences.getInstance(),
        ).state;
        expect(again, isNot(_sameChoices(const IndexView())), reason: what);
      }
    });

    test('lo guardado que no se entiende vuelve a lo de siempre, sin '
        'romperse', () async {
      for (final stored in [
        'no es json',
        '[1, 2]',
        jsonEncode({'arrangement': 'otra', 'depth': 7, 'numbered': 'sí'}),
      ]) {
        final view = (await controller({
          IndexViewController.prefsKey: stored,
        })).state;
        expect(view.arrangement, IndexArrangement.byTopic, reason: stored);
        expect(view.depth, IndexDepth.three, reason: stored);
        expect(view.numbered, isFalse, reason: stored);
      }
    });

    test('elegir los niveles rehace lo abierto a mano dentro de los '
        'documentos, y deja los temas y los documentos como estaban', () async {
      final views = await controller();
      views
        ..toggleTopic('roma')
        ..toggleDocument('a')
        ..toggleChapter('a', 3, unfolded: false)
        ..showDepth(IndexDepth.one);

      expect(views.state.chapterFolds, isEmpty);
      expect(views.state.foldedTopics, {'roma'});
      expect(views.state.openDocuments, {'a'});
    });

    test('abrir un capítulo cambia solo el mapa de su documento', () async {
      final views = await controller();
      views.toggleChapter('a', 3, unfolded: false);
      final other = views.state.chapterFolds['a'];
      views.toggleChapter('b', 9, unfolded: true);

      expect(views.state.chapterFolds['a'], same(other));
      expect(views.state.chapterFolds, {
        'a': {3: true},
        'b': {9: false},
      });
    });

    test(
      'plegar y desplegar va y vuelve; «Sin tema» también se pliega',
      () async {
        final views = await controller();
        views
          ..toggleTopic(null)
          ..toggleDocument('a');
        expect(views.state.foldedTopics, {null});
        expect(views.state.openDocuments, {'a'});

        views
          ..toggleTopic(null)
          ..toggleDocument('a');
        expect(views.state.foldedTopics, isEmpty);
        expect(views.state.openDocuments, isEmpty);
      },
    );

    test('lo buscado va sin espacios en los bordes, y en blanco vuelve al '
        'árbol', () async {
      final views = await controller();
      views.search('  Nicea  ');
      expect(views.state.query, 'Nicea');
      expect(views.state.searching, isTrue);

      views.search('   ');
      expect(views.state.searching, isFalse);
    });
  });

  group('lo que llega', () {
    var now = DateTime(2026, 11, 5, 10);
    late IndexArrivals arrivals;
    setUp(() {
      now = DateTime(2026, 11, 5, 10);
      arrivals = IndexArrivals(() => now);
    });

    test('la primera vez de una lista no llega nada: es lo que había', () {
      arrivals.observe('topic:roma', ['a', 'b']);

      expect(arrivals.freshArrival('a'), isNull);
    });

    test('lo que no estaba la vez anterior llegó, y brilla un rato', () {
      arrivals
        ..observe('topic:roma', ['a'])
        ..observe('topic:roma', ['a', 'b']);

      expect(arrivals.freshArrival('b'), now);
      expect(arrivals.freshArrival('a'), isNull);

      now = now.add(IndexArrivals.glow + const Duration(milliseconds: 1));
      expect(arrivals.freshArrival('b'), isNull);
    });

    test('cada lista se compara consigo misma', () {
      arrivals
        ..observe('topic:roma', ['a'])
        ..observe('topic:grecia', ['b'])
        ..observe('topic:roma', ['a']);

      expect(arrivals.freshArrival('b'), isNull);
    });

    test('las entradas se reconocen por lo que son, no por su clave: volver '
        'a indexar no hace llegar nada', () {
      final before = indexChapters('d', [(1, 'Uno'), (2, 'Dos')]);
      final after = [
        ...indexChapters('d', [(1, 'Uno'), (2, 'Dos')], firstKey: 50),
        indexChapters('d', [(2, 'Tres')], firstKey: 60).single,
      ];

      arrivals
        ..observe('entries:d', indexEntryIdentities(before))
        ..observe('entries:d', indexEntryIdentities(after));

      final ids = indexEntryIdentities(after);
      expect(arrivals.freshArrival(ids[0]), isNull);
      expect(arrivals.freshArrival(ids[1]), isNull);
      expect(arrivals.freshArrival(ids[2]), now);
    });

    test('dos títulos iguales son dos entradas distintas', () {
      final ids = indexEntryIdentities(
        indexChapters('d', [(1, 'Resumen'), (1, 'Resumen')]),
      );

      expect(ids.toSet(), hasLength(2));
    });

    test('una imagen se reconoce por su imagen: renombrarla no la hace '
        'llegar, y otra imagen sí', () {
      String identity(IndexEntry image) => indexEntryIdentities([image]).single;
      final mapa = identity(indexImage('d', 1, position: 0, title: 'Mapa'));

      expect(
        identity(indexImage('d', 1, position: 0, title: 'Mapa de Roma')),
        mapa,
      );
      expect(
        identity(indexImage('d', 7, position: 0, title: 'Mapa')),
        isNot(mapa),
      );
    });
  });
}

/// Si una vista tiene las mismas elecciones que se recuerdan que [expected].
Matcher _sameChoices(IndexView expected) => predicate<IndexView>(
  (view) =>
      view.arrangement == expected.arrangement &&
      view.order == expected.order &&
      view.depth == expected.depth &&
      view.numbered == expected.numbered,
  'las mismas elecciones que la vista de entrada',
);
