import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/map/domain/entities/map_node_facts.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/map_node_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// Lo que dice la ficha de un nodo del lienzo (F44, paso 4), en palabras: lo
/// que tiene y la pregunta de «Preguntar al chat».
void main() {
  final es = AppLocalizationsEs();

  const imperio = MapNodeNeighbor(
    ref: MapCommunityRef(1),
    label: 'Imperio romano · Roma',
    shortLabel: 'Imperio romano',
  );
  const literatura = MapNodeNeighbor(
    ref: MapCommunityRef(2),
    label: 'Literatura',
  );

  MapNodeFacts community({
    List<String> names = const ['Cristianismo', 'Tomás de Aquino'],
    List<MapNodeNeighbor> neighbors = const [],
    int? documents = 7,
    int? links = 2,
  }) => MapNodeFacts(
    ref: const MapCommunityRef(0),
    kind: MapNodeKind.community,
    title: names.join(' · '),
    nameLabels: names,
    topicCount: 3,
    documentCount: documents,
    linkCount: links,
    neighbors: neighbors,
  );

  test('una lista en una frase', () {
    expect(mapListAnd(es, const []), '');
    expect(mapListAnd(es, const ['Roma']), 'Roma');
    expect(mapListAnd(es, const ['Roma', 'Grecia']), 'Roma y Grecia');
    expect(
      mapListAnd(es, const ['Roma', 'Grecia', 'Egipto']),
      'Roma, Grecia y Egipto',
    );
  });

  group('la pregunta de «Preguntar al chat»', () {
    test('una comunidad se nombra por sus temas, y cada vecina por el suyo '
        'principal', () {
      final facts = community(neighbors: const [imperio, literatura]);

      expect(
        mapNodeQuestion(es, facts, facts.title),
        '¿Qué dicen mis documentos sobre Cristianismo y Tomás de Aquino y cómo '
        'se relacionan con Imperio romano y Literatura?',
      );
    });

    test('con un solo tema, en singular; sin vecinos, solo qué dicen', () {
      final single = community(
        names: const ['Cristianismo'],
        neighbors: const [imperio],
      );
      expect(
        mapNodeQuestion(es, single, single.title),
        '¿Qué dicen mis documentos sobre Cristianismo y cómo se relaciona con '
        'Imperio romano?',
      );
      expect(
        mapNodeQuestion(es, community(), 'Cristianismo · Tomás de Aquino'),
        '¿Qué dicen mis documentos sobre Cristianismo y Tomás de Aquino?',
      );
    });

    test('un tema, por su nombre', () {
      const facts = MapNodeFacts(
        ref: MapTopicRef('roma'),
        kind: MapNodeKind.topic,
        title: 'Roma',
        neighbors: [
          MapNodeNeighbor(ref: MapTopicRef('grecia'), label: 'Grecia'),
        ],
      );

      expect(
        mapNodeQuestion(es, facts, 'Roma'),
        '¿Qué dicen mis documentos sobre Roma y cómo se relaciona con Grecia?',
      );
    });

    test('un documento: de qué trata y con qué se relaciona', () {
      const alone = MapNodeFacts(
        ref: MapDocumentRef('d1'),
        kind: MapNodeKind.source,
        title: 'Regla de san Benito',
      );
      const linked = MapNodeFacts(
        ref: MapDocumentRef('d1'),
        kind: MapNodeKind.source,
        title: 'Regla de san Benito',
        neighbors: [
          MapNodeNeighbor(ref: MapDocumentRef('d2'), label: 'Casiano'),
          MapNodeNeighbor(ref: MapDocumentRef('d3'), label: 'Agustín'),
        ],
      );

      expect(
        mapNodeQuestion(es, alone, alone.title),
        '¿De qué trata «Regla de san Benito»?',
      );
      expect(
        mapNodeQuestion(es, linked, linked.title),
        '¿De qué trata «Regla de san Benito» y cómo se relaciona con Casiano y '
        'Agustín?',
      );
    });

    test('lo que junta varias comunidades no es un tema del que preguntar', () {
      const group = MapNodeFacts(
        ref: MapCommunityRef(5),
        kind: MapNodeKind.group,
        title: '',
        topicCount: 4,
      );

      expect(mapNodeQuestion(es, group, 'Otras comunidades'), isNull);
    });
  });

  group('lo que tiene, en una línea', () {
    test('una comunidad: documentos, temas y vínculos; sin lo que calcula el '
        'motor, solo sus temas', () {
      expect(
        mapNodeFactsLine(es, community(), 'spaces'),
        '7 documentos · 3 temas · 2 vínculos',
      );
      expect(
        mapNodeFactsLine(es, community(documents: null, links: null), 'tags'),
        '3 etiquetas',
      );
    });

    test('un tema: sus documentos y con cuántos se une', () {
      const facts = MapNodeFacts(
        ref: MapTopicRef('roma'),
        kind: MapNodeKind.topic,
        title: 'Roma',
        topicCount: 1,
        documentCount: 1,
      );

      expect(
        mapNodeFactsLine(es, facts, 'spaces'),
        '1 documento · unido a 1 tema',
      );
    });

    test('un documento: qué es y cuántos vínculos suyos se ven', () {
      const note = MapNodeFacts(
        ref: MapDocumentRef('n1'),
        kind: MapNodeKind.note,
        title: 'Mi nota',
        linkCount: 0,
      );
      const source = MapNodeFacts(
        ref: MapDocumentRef('s1'),
        kind: MapNodeKind.source,
        title: 'Livio',
      );

      expect(
        mapNodeFactsLine(es, note, 'spaces'),
        'Nota · ningún vínculo a la vista',
      );
      expect(mapNodeFactsLine(es, source, 'spaces'), 'Fuente');
    });

    test('un grupo: cuántos temas junta', () {
      const group = MapNodeFacts(
        ref: MapCommunityRef(5),
        kind: MapNodeKind.group,
        title: '',
        topicCount: 4,
      );

      expect(mapNodeFactsLine(es, group, 'spaces'), '4 temas');
    });
  });

  group('las acciones de la ficha', () {
    final calls = <Object>[];
    final MapNodeHandlers on = (
      enter: (node) => calls.add('enter:${node.sceneKey}'),
      center: (node) => calls.add('center:${node.sceneKey}'),
      exitFocus: () => calls.add('exit'),
      openTopic: (valueId) => calls.add('topic:$valueId'),
      openItem: (itemId) => calls.add('item:$itemId'),
      ask: (question) => calls.add('ask:$question'),
      study: calls.add,
      link: (itemId) => calls.add('link:$itemId'),
      seeLinks: (itemId) => calls.add('links:$itemId'),
    );
    const topic = MapNodeFacts(
      ref: MapTopicRef('roma'),
      kind: MapNodeKind.topic,
      title: 'Roma',
    );
    const document = MapNodeFacts(
      ref: MapDocumentRef('d1'),
      kind: MapNodeKind.source,
      title: 'Livio',
    );

    List<MapNodeAction> actionsOf(
      MapNodeFacts facts, {
      bool centered = false,
      bool showingItsLinks = false,
      bool spaces = true,
    }) => mapNodeActions(
      es,
      facts,
      title: facts.title,
      centered: centered,
      showingItsLinks: showingItsLinks,
      spaces: spaces,
      on: on,
    );
    List<String> ids(MapNodeFacts facts, {bool showingItsLinks = false}) => [
      for (final action in actionsOf(facts, showingItsLinks: showingItsLinks))
        action.id,
    ];

    setUp(calls.clear);

    test('lo que junta temas: Entrar primero; un grupo, solo eso', () {
      expect(ids(community()), ['enter', 'center', 'ask']);
      expect(
        ids(
          const MapNodeFacts(
            ref: MapCommunityRef(5),
            kind: MapNodeKind.group,
            title: '',
          ),
        ),
        ['enter'],
      );
      expect(ids(topic), ['enter', 'center', 'open', 'ask', 'study']);
    });

    test('un documento: Abrir primero, y Vincular y Ver sus vínculos, salvo '
        'que ya se estén viendo', () {
      expect(ids(document), [
        'open',
        'center',
        'ask',
        'study',
        'link',
        'see-links',
      ]);
      expect(ids(document, showingItsLinks: true), [
        'open',
        'center',
        'ask',
        'study',
        'link',
      ]);
    });

    test('con el nodo en el centro, Salir del foco en vez de Centrar aquí', () {
      final actions = actionsOf(topic, centered: true);

      expect(actions.map((a) => a.id), contains('exit-focus'));
      expect(actions.map((a) => a.id), isNot(contains('center')));
      actions.singleWhere((a) => a.id == 'exit-focus').onPressed();
      expect(calls, ['exit']);
    });

    test('cada una hace lo suyo, con lo que le toca', () {
      for (final action in [...actionsOf(topic), ...actionsOf(document)]) {
        action.onPressed();
      }
      // Un tema de F37 se estudia como espacio; uno de una categoría, con
      // sus ramas.
      actionsOf(
        topic,
        spaces: false,
      ).singleWhere((a) => a.id == 'study').onPressed();

      expect(calls, [
        'enter:topic:roma',
        'center:topic:roma',
        'topic:roma',
        'ask:${es.f44S4AskAbout('Roma')}',
        const CreationScope.space('roma'),
        'item:d1',
        'center:item:d1',
        'ask:${es.f44S4AskDocument('Livio')}',
        const CreationScope.document('d1'),
        'link:d1',
        'links:d1',
        const CreationScope.topic('roma'),
      ]);
    });
  });
}
