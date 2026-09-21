import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/atlas/domain/services/atlas_builder.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/knowledge_map_state.dart';
import 'package:sinapsis/features/map/domain/entities/map_dashboard.dart';
import 'package:sinapsis/features/map/domain/entities/schema.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/entities/topic_items.dart';
import 'package:sinapsis/features/map/domain/repositories/knowledge_map_repository.dart';
import 'package:sinapsis/features/map/domain/services/knowledge_map_engine.dart';
import 'package:sinapsis/features/map/domain/services/schema_tree_builder.dart';
import 'package:sinapsis/features/map/presentation/providers/map_providers.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_schema_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// Un repositorio a mano: lo único que el esquema le pide es lo que cuelga de
/// un nodo.
class _FakeRepository implements KnowledgeMapRepository {
  final links = <String, List<SchemaLink>>{};
  final requested = <String>[];
  final mapNotes = <SchemaLink>[];

  @override
  Future<List<SchemaLink>> readMapNotes({int limit = kMaxMapNotes}) async =>
      mapNotes;

  @override
  Future<List<SchemaLink>> schemaLinks(
    SchemaRef node, {
    int limit = kSchemaFanOut,
  }) async {
    requested.add(node.key);
    return links[node.key] ?? const [];
  }

  @override
  Future<TopicGraphInput> readTopicInput(
    String definitionId, {
    LibraryQuery filter = const LibraryQuery(),
  }) => throw UnimplementedError();

  @override
  Future<MapDashboard> readDashboard({
    LibraryQuery filter = const LibraryQuery(),
  }) => throw UnimplementedError();

  @override
  Future<TopicItemsGraph> readTopicItems(
    String valueId, {
    int limit = kMaxGraphItems,
  }) => throw UnimplementedError();

  @override
  Stream<void> changes({LibraryQuery filter = const LibraryQuery()}) =>
      const Stream.empty();
}

/// El esquema del mapa (F14, D6) como widget: parte de un tema, se despliega al
/// tocarlo y muestra lo que la base trae de cada nodo.
void main() {
  final es = AppLocalizationsEs();
  late _FakeRepository repository;

  /// roma ─ república ─ gracos, roma ─ imperio; grecia sola.
  KnowledgeMapSnapshot snapshot({int sequence = 1, bool withRoma = true}) {
    final input = TopicGraphInput(
      definitionId: 'tema',
      definitionName: 'Tema',
      values: [
        if (withRoma) const AtlasValueRow(id: 'roma', label: 'Roma'),
        AtlasValueRow(
          id: 'republica',
          label: 'República',
          parentId: withRoma ? 'roma' : null,
        ),
        const AtlasValueRow(
          id: 'gracos',
          label: 'Gracos',
          parentId: 'republica',
        ),
        AtlasValueRow(
          id: 'imperio',
          label: 'Imperio',
          parentId: withRoma ? 'roma' : null,
        ),
        const AtlasValueRow(id: 'grecia', label: 'Grecia'),
      ],
      items: [
        for (var i = 0; i < 5; i++)
          TopicItem(
            id: 'r$i',
            valueIds: [if (withRoma) 'roma' else 'republica'],
          ),
        const TopicItem(id: 'g', valueIds: ['grecia']),
      ],
      relations: const [],
    );
    final computed = computeMap(input, const CommunityMemory.none());
    return KnowledgeMapSnapshot(
      request: const MapRequest('tema'),
      graph: computed.graph,
      detection: computed.detection,
      timings: const MapTimings(
        read: Duration.zero,
        build: Duration.zero,
        communities: Duration.zero,
        total: Duration.zero,
      ),
      sequence: sequence,
    );
  }

  final opened = <String>[];

  Widget app(KnowledgeMapSnapshot map) => ProviderScope(
    overrides: [knowledgeMapRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MapSchemaView(
          snapshot: map,
          onOpenTopic: (id) => opened.add('topic:$id'),
          onOpenItem: (id) => opened.add('item:$id'),
        ),
      ),
    ),
  );

  Future<void> pump(WidgetTester tester, [KnowledgeMapSnapshot? map]) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(map ?? snapshot()));
    await tester.pumpAndSettle();
  }

  Finder node(String key) => find.byKey(ValueKey('map-schema-node-$key'));

  setUp(() {
    repository = _FakeRepository();
    opened.clear();
  });

  testWidgets('parte del tema de primer nivel con más elementos, ya '
      'desplegado', (tester) async {
    await pump(tester);

    expect(node('topic:roma'), findsOneWidget);
    expect(node('topic:imperio'), findsOneWidget);
    expect(node('topic:republica'), findsOneWidget);
    // Grecia tiene menos elementos: no es la raíz.
    expect(node('topic:grecia'), findsNothing);
    // Lo que no se desplegó no se ve.
    expect(node('topic:gracos'), findsNothing);
  });

  testWidgets('tocar un nodo con hijos lo despliega, y otra vez lo pliega', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(node('topic:republica'));
    await tester.pumpAndSettle();
    expect(node('topic:gracos'), findsOneWidget);

    await tester.tap(node('topic:republica'));
    await tester.pumpAndSettle();
    expect(node('topic:gracos'), findsNothing);
  });

  testWidgets('al desplegar un tema se pide a la base lo que le cuelga, y las '
      'notas mapa aparecen', (tester) async {
    repository.links['topic:roma'] = const [
      SchemaLink(
        target: SchemaRef.item('n1'),
        title: 'Mapa de Roma',
        edge: SchemaEdgeKind.mapNote,
        isNote: true,
      ),
    ];
    await pump(tester);

    expect(repository.requested, contains('topic:roma'));
    expect(node('item:n1'), findsOneWidget);
    expect(find.text('Mapa de Roma'), findsOneWidget);
  });

  testWidgets('desplegar una nota trae sus vínculos, con el tipo de cada uno', (
    tester,
  ) async {
    repository
      ..links['topic:roma'] = const [
        SchemaLink(
          target: SchemaRef.item('n1'),
          title: 'Mapa de Roma',
          edge: SchemaEdgeKind.mapNote,
          isNote: true,
        ),
      ]
      ..links['item:n1'] = const [
        SchemaLink(
          target: SchemaRef.item('s1'),
          title: 'Livio',
          edge: SchemaEdgeKind.relation,
          relation: RelationKind.indexes,
        ),
        SchemaLink(
          target: SchemaRef.item('s2'),
          title: 'Polibio',
          edge: SchemaEdgeKind.relation,
          relation: RelationKind.contradicts,
          outgoing: false,
        ),
      ];
    await pump(tester);

    await tester.tap(node('item:n1'));
    await tester.pumpAndSettle();

    expect(repository.requested, contains('item:n1'));
    expect(node('item:s1'), findsOneWidget);
    expect(node('item:s2'), findsOneWidget);
    expect(find.text('Livio'), findsOneWidget);
  });

  testWidgets('un nodo sin nada que desplegar se abre al tocarlo', (
    tester,
  ) async {
    repository.links['topic:imperio'] = const [];
    await pump(tester);
    // Se pide lo de Imperio para saber que no tiene notas.
    await tester.tap(node('topic:imperio'));
    await tester.pumpAndSettle();
    await tester.tap(node('topic:imperio'));
    await tester.pumpAndSettle();

    expect(opened, ['topic:imperio']);
  });

  testWidgets('el botón de cada nodo abre el tema o el elemento', (
    tester,
  ) async {
    repository.links['topic:roma'] = const [
      SchemaLink(
        target: SchemaRef.item('n1'),
        title: 'Mapa de Roma',
        edge: SchemaEdgeKind.mapNote,
        isNote: true,
      ),
    ];
    await pump(tester);

    await tester.tap(find.byKey(const ValueKey('map-schema-open-topic:roma')));
    await tester.tap(find.byKey(const ValueKey('map-schema-open-item:n1')));

    expect(opened, ['topic:roma', 'item:n1']);
  });

  testWidgets('en modo árbol, los hijos quedan debajo de la raíz', (
    tester,
  ) async {
    await pump(tester);
    final radialRoot = tester.getCenter(node('topic:roma'));
    final radialChild = tester.getCenter(node('topic:imperio'));

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('map-schema-mode')),
        matching: find.byIcon(Icons.account_tree_outlined),
      ),
    );
    await tester.pumpAndSettle();

    final root = tester.getCenter(node('topic:roma'));
    final child = tester.getCenter(node('topic:imperio'));
    expect(child.dy, greaterThan(root.dy));
    // Y el radial era otra disposición.
    expect(
      (radialChild - radialRoot).direction,
      isNot((child - root).direction),
    );
  });

  testWidgets('elegir otro tema de partida', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const ValueKey('map-schema-root')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('map-schema-search')),
      'grec',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('map-schema-pick-roma')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('map-schema-pick-grecia')));
    await tester.pumpAndSettle();

    expect(node('topic:grecia'), findsOneWidget);
    expect(node('topic:roma'), findsNothing);
  });

  testWidgets('el selector ofrece también las notas mapa, y se puede partir '
      'de una', (tester) async {
    repository
      ..mapNotes.add(
        const SchemaLink(
          target: SchemaRef.item('n1'),
          title: 'Mapa de Roma',
          edge: SchemaEdgeKind.mapNote,
          isNote: true,
        ),
      )
      ..links['item:n1'] = const [
        SchemaLink(
          target: SchemaRef.item('s1'),
          title: 'Livio',
          edge: SchemaEdgeKind.relation,
          relation: RelationKind.indexes,
        ),
      ];
    await pump(tester);

    await tester.tap(find.byKey(const ValueKey('map-schema-root')));
    await tester.pumpAndSettle();
    expect(find.text(es.mapSchemaPickerMapNotes), findsOneWidget);
    expect(find.text(es.mapSchemaPickerTopics), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('map-schema-pick-note-n1')));
    await tester.pumpAndSettle();

    // La raíz es la nota, con su nombre, y trae sus vínculos.
    expect(node('item:n1'), findsOneWidget);
    expect(node('topic:roma'), findsNothing);
    expect(find.text('Mapa de Roma'), findsWidgets);
    expect(repository.requested, contains('item:n1'));
    expect(node('item:s1'), findsOneWidget);
  });

  testWidgets('buscar en el selector filtra también las notas mapa', (
    tester,
  ) async {
    repository.mapNotes.addAll(const [
      SchemaLink(
        target: SchemaRef.item('n1'),
        title: 'Mapa de Roma',
        edge: SchemaEdgeKind.mapNote,
        isNote: true,
      ),
      SchemaLink(
        target: SchemaRef.item('n2'),
        title: 'Mapa de Egipto',
        edge: SchemaEdgeKind.mapNote,
        isNote: true,
      ),
    ]);
    await pump(tester);

    await tester.tap(find.byKey(const ValueKey('map-schema-root')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('map-schema-search')),
      'egip',
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('map-schema-pick-note-n2')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('map-schema-pick-note-n1')), findsNothing);
  });

  testWidgets('un esquema con demasiados nodos avisa de los que no dibuja', (
    tester,
  ) async {
    repository.links['topic:roma'] = [
      for (var i = 0; i < kMaxSchemaNodes + 20; i++)
        SchemaLink(
          target: SchemaRef.item('n$i'),
          title: 'Nota $i',
          edge: SchemaEdgeKind.mapNote,
          isNote: true,
        ),
    ];
    await pump(tester);

    expect(find.byKey(const ValueKey('map-schema-truncated')), findsOneWidget);
    expect(find.text(es.mapSchemaTruncated(kMaxSchemaNodes)), findsOneWidget);
  });

  testWidgets('si el mapa se recalcula y el tema de partida ya no existe, '
      'parte de otro', (tester) async {
    await pump(tester);
    expect(node('topic:roma'), findsOneWidget);

    await tester.pumpWidget(app(snapshot(sequence: 2, withRoma: false)));
    await tester.pumpAndSettle();

    expect(node('topic:roma'), findsNothing);
    // República pasa a ser de primer nivel, y con más elementos que Grecia.
    expect(node('topic:republica'), findsOneWidget);
  });

  testWidgets('cada nodo tiene una descripción accesible con lo que es', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    repository.links['topic:roma'] = const [
      SchemaLink(
        target: SchemaRef.item('n1'),
        title: 'Mapa de Roma',
        edge: SchemaEdgeKind.mapNote,
        isNote: true,
      ),
    ];
    await pump(tester);

    expect(
      tester.getSemantics(node('topic:roma')).label,
      '${es.mapSchemaNodeTopic}: Roma',
    );
    expect(
      tester.getSemantics(node('item:n1')).label,
      '${es.mapSchemaNodeMapNote}: Mapa de Roma',
    );
    handle.dispose();
  });
}
