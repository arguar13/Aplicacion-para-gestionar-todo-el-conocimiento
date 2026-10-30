import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/topic_dimension.dart';
import 'package:sinapsis/features/atlas/domain/services/atlas_builder.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/knowledge_map_state.dart';
import 'package:sinapsis/features/map/domain/entities/link_graph.dart';
import 'package:sinapsis/features/map/domain/entities/map_dashboard.dart';
import 'package:sinapsis/features/map/domain/entities/schema.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/entities/topic_items.dart';
import 'package:sinapsis/features/map/domain/repositories/knowledge_map_repository.dart';
import 'package:sinapsis/features/map/domain/services/knowledge_map_engine.dart';
import 'package:sinapsis/features/map/domain/services/link_strength.dart';
import 'package:sinapsis/features/map/presentation/providers/map_canvas_request.dart';
import 'package:sinapsis/features/map/presentation/providers/map_layout_runner.dart';
import 'package:sinapsis/features/map/presentation/providers/map_providers.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/canvas_network.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/canvas_tree.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/map_canvas_view.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_edges_painter.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_export_handle.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_item_box.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// Un repositorio a mano: lo que el lienzo le pide son los documentos de un
/// tema, lo que cuelga de un nodo de Radial y Árbol y las notas mapa.
class _FakeRepository implements KnowledgeMapRepository {
  final requested = <String>[];
  final schemaRequested = <String>[];
  final links = <String, List<SchemaLink>>{};
  final mapNotes = <SchemaLink>[];

  @override
  Future<TopicItemsGraph> readTopicItems(
    String valueId, {
    String? dimensionId,
    int limit = kMaxGraphItems,
    LibraryScope scope = LibraryScope.processed,
  }) async {
    requested.add(valueId);
    return TopicItemsGraph(
      valueId: valueId,
      items: const [
        TopicItemNode(id: 'i1', title: 'Livio', isNote: false),
        TopicItemNode(id: 'i2', title: 'Mi nota', isNote: true),
      ],
      edges: const [TopicItemEdge(a: 1, b: 0, kind: RelationKind.cites)],
      truncated: false,
    );
  }

  @override
  Future<List<SchemaLink>> schemaLinks(
    SchemaRef node, {
    String? dimensionId,
    int limit = kSchemaFanOut,
  }) async {
    schemaRequested.add(node.key);
    return links[node.key] ?? const [];
  }

  @override
  Future<List<SchemaLink>> readMapNotes({int limit = kMaxMapNotes}) async =>
      mapNotes;

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
  Future<LinkGraph> readLinkGraph({
    LibraryQuery filter = const LibraryQuery(),
    String? focusId,
    int limit = kMaxGraphItems,
    LinkStrengthFilter strength = LinkStrengthFilter.all,
  }) => throw UnimplementedError();

  @override
  Stream<void> changes({LibraryQuery filter = const LibraryQuery()}) =>
      const Stream.empty();
}

/// El lienzo único del Mapa (F44, paso 2) como widget: las tres alturas, Red ·
/// Radial · Árbol, el minimapa, ⊕ ⊖ ⛶, la exportación, «Ver como lista» y los
/// vínculos entre documentos.
void main() {
  final es = AppLocalizationsEs();
  late _FakeRepository repository;
  final opened = <String>[];
  final linkRequests = <MapLinksRequest>[];
  late ProviderContainer container;

  /// Dos comunidades de temas muy unidos entre sí —Alfa, de [alfaSize], y
  /// Beta, de cuatro— con un vínculo entre las dos, y temas aislados.
  KnowledgeMapSnapshot snapshot({
    int sequence = 1,
    bool withBeta = true,
    int isolatedTopics = 1,
    int alfaSize = 4,
    bool empty = false,
  }) {
    final alfa = [for (var i = 1; i <= alfaSize; i++) 'a$i'];
    final beta = withBeta ? ['b1', 'b2', 'b3', 'b4'] : <String>[];
    final items = <TopicItem>[];
    for (final group in [alfa, beta]) {
      for (var i = 0; i < group.length; i++) {
        for (var j = i + 1; j < group.length; j++) {
          for (var k = 0; k < 4; k++) {
            items.add(
              TopicItem(
                id: 'x-${group[i]}-${group[j]}-$k',
                valueIds: [group[i], group[j]],
              ),
            );
          }
        }
      }
    }
    final input = TopicGraphInput(
      definitionId: 'tema',
      definitionName: 'Tema',
      values: empty
          ? const []
          : [
              for (final id in alfa)
                AtlasValueRow(id: id, label: 'Alfa ${id.substring(1)}'),
              for (final id in beta)
                AtlasValueRow(id: id, label: 'Beta ${id.substring(1)}'),
              for (var i = 0; i < isolatedTopics; i++)
                AtlasValueRow(
                  id: 'solo$i',
                  label: 'Solo ${i.toString().padLeft(3, '0')}',
                ),
            ],
      items: empty ? const [] : items,
      relations: [
        if (withBeta && !empty)
          const TopicRelation(
            fromItemId: 'x-a1-a2-0',
            toItemId: 'x-b1-b2-0',
            kind: RelationKind.relatedTo,
          ),
      ],
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

  /// Tres documentos vinculados —a con b, b con c— y uno suelto; con un corte
  /// por fuerza, solo el primer vínculo.
  LinkGraph linkGraph(MapLinksRequest request) {
    final cut = request.strength != LinkStrengthFilter.all;
    return LinkGraph(
      items: [
        const TopicItemNode(id: 'a', title: 'Documento a', isNote: false),
        const TopicItemNode(id: 'b', title: 'Documento b', isNote: true),
        if (!cut)
          const TopicItemNode(id: 'c', title: 'Documento c', isNote: false),
      ],
      edges: [
        const TopicItemEdge(a: 0, b: 1, kind: RelationKind.contradicts),
        if (!cut) const TopicItemEdge(a: 1, b: 2, kind: RelationKind.cites),
      ],
      linkedCount: 3,
      unlinkedCount: 1,
      focusId: request.focusId,
      totalLinks: 2,
      shownLinks: cut ? 1 : 2,
    );
  }

  MapExportHandle? handle;

  Widget app(
    KnowledgeMapSnapshot map, {
    ThemeData? theme,
    double textScale = 1,
  }) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: const Locale('es'),
      theme: theme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: MapCanvasView(
          snapshot: map,
          dimension: const TopicDimension.spaces(),
          filter: const LibraryQuery(),
          exportHandle: handle,
          onOpenTopic: (id) => opened.add('topic:$id'),
          onOpenItem: (id) => opened.add('item:$id'),
        ),
      ),
    ),
  );

  Future<void> pump(
    WidgetTester tester, [
    KnowledgeMapSnapshot? map,
    Size size = const Size(1000, 900),
  ]) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(map ?? snapshot()));
    await tester.pumpAndSettle();
  }

  Finder node(String key) => find.byKey(ValueKey('map-node-$key'));
  Finder card(String key) => find.byKey(ValueKey('map-tree-node-$key'));
  Finder crumb(String level) => find.byKey(ValueKey('map-crumb-$level'));
  final canvas = find.byKey(const ValueKey('map-canvas'));

  InteractiveViewer viewer(WidgetTester tester) =>
      tester.widget<InteractiveViewer>(canvas);
  double scaleOf(WidgetTester tester) =>
      viewer(tester).transformationController!.value.getMaxScaleOnAxis();

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> arrange(WidgetTester tester, IconData icon) => tapAndSettle(
    tester,
    find.descendant(
      of: find.byKey(const ValueKey('map-arrangement')),
      matching: find.byIcon(icon),
    ),
  );

  setUp(() {
    repository = _FakeRepository();
    opened.clear();
    linkRequests.clear();
    handle = null;
    container = ProviderContainer(
      overrides: [
        knowledgeMapRepositoryProvider.overrideWithValue(repository),
        mapLayoutRunnerProvider.overrideWithValue(
          (job) async => runLayout(job),
        ),
        mapLinksProvider.overrideWith((ref, request) {
          linkRequests.add(request);
          return Stream.value(linkGraph(request));
        }),
      ],
    );
    addTearDown(container.dispose);
  });

  test('los datos de las pruebas dan dos comunidades y un aislado', () {
    final map = snapshot();

    final connected = map.detection.communities.where((c) => !c.isIsolated);
    expect(connected, hasLength(2));
    expect(connected.every((c) => c.members.length == 4), isTrue);
    expect(map.detection.communities.where((c) => c.isIsolated), hasLength(1));
  });

  group('las tres alturas, en la red', () {
    testWidgets('de lejos: un nodo por comunidad y uno para los aislados', (
      tester,
    ) async {
      await pump(tester);

      expect(node('overview:0'), findsOneWidget);
      expect(node('overview:1'), findsOneWidget);
      expect(node('overview:2'), findsOneWidget);
      expect(find.text(es.mapGraphHint), findsOneWidget);
      expect(crumb('overview'), findsOneWidget);
      expect(find.text(es.f44S2CrumbAll), findsOneWidget);
      expect(crumb('topics'), findsNothing);
      // El nodo de los aislados se rotula solo.
      expect(find.text(es.mapBoardIsolatedTitle('spaces')), findsOneWidget);
    });

    testWidgets('tocar una comunidad muestra sus temas, y la miga vuelve', (
      tester,
    ) async {
      await pump(tester);

      await tapAndSettle(tester, node('overview:0'));

      for (final id in ['a1', 'a2', 'a3', 'a4']) {
        expect(node('topic:$id'), findsOneWidget);
      }
      // Beta se une a Alfa por un vínculo: sus temas vecinos entran, el resto
      // no.
      expect(node('topic:b1'), findsOneWidget);
      expect(node('topic:b3'), findsNothing);
      expect(node('overview:0'), findsNothing);
      expect(crumb('topics'), findsOneWidget);

      await tapAndSettle(tester, crumb('overview'));

      expect(node('overview:0'), findsOneWidget);
      expect(node('topic:a1'), findsNothing);
    });

    testWidgets('en los temas se elige el grado: 0, solo la comunidad; todos, '
        'lo que se alcanza; de lejos no está', (tester) async {
      await pump(tester);
      final degree = find.byKey(const ValueKey('map-degree'));
      Finder chip(String label) => find.descendant(
        of: degree,
        matching: find.widgetWithText(ChoiceChip, label),
      );

      expect(degree, findsNothing);

      await tapAndSettle(tester, node('overview:0'));
      expect(tester.widget<ChoiceChip>(chip('1')).selected, isTrue);

      await tapAndSettle(tester, chip('0'));

      expect(node('topic:a1'), findsOneWidget);
      expect(node('topic:b1'), findsNothing);

      await tapAndSettle(tester, chip(es.graphDegreeAll));

      expect(node('topic:b1'), findsOneWidget);
      expect(node('topic:b3'), findsOneWidget);
    });

    testWidgets('tocar un tema despliega sus documentos alrededor, y tocar un '
        'documento lo abre', (tester) async {
      await pump(tester);
      await tapAndSettle(tester, node('overview:0'));

      await tapAndSettle(tester, node('topic:a1'));

      expect(repository.requested, ['a1']);
      expect(node('item:i1'), findsOneWidget);
      expect(node('item:i2'), findsOneWidget);
      expect(
        find.descendant(of: crumb('documents'), matching: find.text('Alfa 1')),
        findsOneWidget,
      );

      await tester.tap(node('item:i1'));
      expect(opened, ['item:i1']);
    });

    testWidgets('con los documentos de un tema, «Ver el material» abre el '
        'tema, y la miga vuelve a los temas', (tester) async {
      await pump(tester);
      await tapAndSettle(tester, node('overview:0'));
      expect(find.byKey(const ValueKey('map-open-topic')), findsNothing);
      await tapAndSettle(tester, node('topic:a2'));

      await tapAndSettle(tester, find.byKey(const ValueKey('map-open-topic')));
      expect(opened, ['topic:a2']);

      await tapAndSettle(tester, crumb('topics'));

      expect(node('topic:a1'), findsOneWidget);
      expect(node('item:i1'), findsNothing);
    });

    testWidgets('«Sugerir vínculos con IA» solo con documentos a la vista; '
        'agregar un vínculo, siempre', (tester) async {
      await pump(tester);
      final suggest = find.byKey(const ValueKey('map-ai-suggest'));
      final add = find.byKey(const ValueKey('map-add-link'));

      expect(suggest, findsNothing);
      expect(add, findsOneWidget);

      await tapAndSettle(tester, node('overview:0'));
      await tapAndSettle(tester, node('topic:a1'));

      expect(suggest, findsOneWidget);
      expect(add, findsOneWidget);
    });
  });

  group('con el zoom', () {
    void zoom(WidgetTester tester, double scale) {
      viewer(tester).transformationController!.value = Matrix4.diagonal3Values(
        scale,
        scale,
        scale,
      );
      viewer(tester).onInteractionEnd!(ScaleEndDetails());
    }

    testWidgets('acercarse mucho pasa a los temas del nodo del centro', (
      tester,
    ) async {
      await pump(tester);

      zoom(tester, kZoomInThreshold + 0.5);
      await tester.pumpAndSettle();

      expect(node('overview:0'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('map-node-topic:'),
        ),
        findsWidgets,
      );
    });

    testWidgets('un zoom moderado no cambia de altura', (tester) async {
      await pump(tester);

      zoom(tester, scaleOf(tester) * 1.5);
      await tester.pumpAndSettle();

      expect(node('overview:0'), findsOneWidget);
    });

    testWidgets('alejarse mucho vuelve a la altura anterior', (tester) async {
      await pump(tester);
      await tapAndSettle(tester, node('overview:0'));
      expect(node('topic:a1'), findsOneWidget);

      zoom(tester, kZoomOutThreshold - 0.1);
      await tester.pumpAndSettle();

      expect(node('overview:0'), findsOneWidget);
      expect(node('topic:a1'), findsNothing);
    });

    group('con la altura encuadrada muy alejada', () {
      // Un celular angosto: los temas de una comunidad quedan encuadrados
      // por debajo del umbral de alejamiento.
      const narrow = Size(120, 420);

      /// Un gesto entero: empieza con el zoom de ahora, lo deja en [scale]
      /// veces el que tenía, más lo que se corrió, y termina.
      void gesture(
        WidgetTester tester, {
        double scale = 1,
        Offset pan = Offset.zero,
      }) {
        final v = viewer(tester);
        final controller = v.transformationController!;
        v.onInteractionStart!(ScaleStartDetails());
        final now = controller.value.getMaxScaleOnAxis();
        controller.value = Matrix4.diagonal3Values(
          now * scale,
          now * scale,
          now * scale,
        )..setTranslationRaw(pan.dx, pan.dy, 0);
        v.onInteractionEnd!(ScaleEndDetails());
      }

      Future<void> openAlfaTopics(WidgetTester tester) async {
        // Una sola comunidad, de treinta temas: acercarse en el centro cae
        // siempre en ella, y sus temas no caben a un zoom grande.
        await pump(
          tester,
          snapshot(withBeta: false, isolatedTopics: 0, alfaSize: 30),
          narrow,
        );
        gesture(tester, scale: 8);
        await tester.pumpAndSettle();
        expect(node('topic:a1'), findsOneWidget);
        // La premisa: el encuadre quedó por debajo del umbral de alejamiento.
        expect(scaleOf(tester), lessThan(kZoomOutThreshold));
      }

      testWidgets('arrastrar el mapa no lo saca de la altura', (tester) async {
        await openAlfaTopics(tester);

        gesture(tester, pan: const Offset(-30, -20));
        await tester.pumpAndSettle();
        gesture(tester, scale: 1.02, pan: const Offset(20, 10));
        await tester.pumpAndSettle();

        expect(node('topic:a1'), findsOneWidget);
        expect(node('overview:0'), findsNothing);
      });

      testWidgets('alejarse un poco más sí vuelve a la altura anterior', (
        tester,
      ) async {
        await openAlfaTopics(tester);

        gesture(tester, scale: 0.8);
        await tester.pumpAndSettle();

        expect(node('overview:0'), findsOneWidget);
        expect(node('topic:a1'), findsNothing);
      });

      testWidgets('acercarse a tres veces el encuadre pasa a la altura '
          'siguiente sin llegar al umbral absoluto', (tester) async {
        await openAlfaTopics(tester);
        final fit = scaleOf(tester);
        expect(fit * kZoomInFromFit, lessThan(kZoomInThreshold));

        gesture(tester, scale: kZoomInFromFit + 0.5);
        await tester.pumpAndSettle();

        expect(node('topic:a1'), findsNothing);
        expect(node('item:i1'), findsOneWidget);
      });

      testWidgets('acercarse menos que eso no cambia de altura', (
        tester,
      ) async {
        await openAlfaTopics(tester);

        gesture(tester, scale: 2);
        await tester.pumpAndSettle();

        expect(node('topic:a1'), findsOneWidget);
      });
    });

    testWidgets('⊕ y ⊖ acercan y alejan alrededor del centro sin cambiar de '
        'altura; ⛶ encuadra todo', (tester) async {
      await pump(tester);
      final fit = scaleOf(tester);

      await tapAndSettle(tester, find.byKey(const ValueKey('map-zoom-in')));
      expect(scaleOf(tester), closeTo(fit * 1.5, 1e-9));
      await tapAndSettle(tester, find.byKey(const ValueKey('map-zoom-in')));
      expect(scaleOf(tester), closeTo(fit * 2.25, 1e-9));
      // Acercar con los botones no baja de altura: no es un gesto.
      expect(node('overview:0'), findsOneWidget);

      await tapAndSettle(tester, find.byKey(const ValueKey('map-zoom-out')));
      expect(scaleOf(tester), closeTo(fit * 1.5, 1e-9));

      await tapAndSettle(tester, find.byKey(const ValueKey('map-fit')));
      expect(scaleOf(tester), closeTo(fit, 1e-9));
    });
  });

  group('el minimapa', () {
    final minimap = find.byKey(const ValueKey('map-minimap'));

    testWidgets('con todo a la vista no está; acercándose, aparece', (
      tester,
    ) async {
      await pump(tester);
      expect(minimap, findsNothing);

      for (var i = 0; i < 3; i++) {
        await tapAndSettle(tester, find.byKey(const ValueKey('map-zoom-in')));
      }

      expect(minimap, findsOneWidget);

      await tapAndSettle(tester, find.byKey(const ValueKey('map-fit')));
      expect(minimap, findsNothing);
    });

    testWidgets('tocarlo lleva ahí, con el mismo zoom', (tester) async {
      await pump(tester);
      for (var i = 0; i < 3; i++) {
        await tapAndSettle(tester, find.byKey(const ValueKey('map-zoom-in')));
      }
      final controller = viewer(tester).transformationController!;
      final viewport = tester.getSize(canvas);
      Offset middle() => controller.toScene(viewport.center(Offset.zero));
      final before = middle();
      final scale = scaleOf(tester);

      // La esquina de arriba a la izquierda del minimapa.
      await tester.tapAt(tester.getTopLeft(minimap) + const Offset(6, 6));
      await tester.pumpAndSettle();

      expect(scaleOf(tester), closeTo(scale, 1e-9));
      final after = middle();
      expect(after.dx, lessThan(before.dx));
      expect(after.dy, lessThan(before.dy));
    });
  });

  group('salir de la burbuja (F44, paso 2)', () {
    testWidgets('al entrar en una comunidad, sus temas nacen donde estaba y se '
        'acomodan', (tester) async {
      await pump(tester);
      final bubble = tester.getCenter(node('overview:0'));

      await tester.tap(node('overview:0'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      final early = tester.getCenter(node('topic:a1'));
      final fading = tester.widget<Opacity>(
        find.ancestor(of: node('topic:a1'), matching: find.byType(Opacity)),
      );
      await tester.pumpAndSettle();
      final settled = tester.getCenter(node('topic:a1'));

      expect(fading.opacity, lessThan(1));
      expect(
        (early - bubble).distance,
        lessThan((settled - bubble).distance * 0.6),
      );
      // Al llegar, el dibujo vuelve a ser el de siempre.
      expect(
        find.ancestor(of: node('topic:a1'), matching: find.byType(Opacity)),
        findsNothing,
      );
    });

    testWidgets('al subir, lo que se miraba se recoge antes de que aparezcan '
        'las comunidades', (tester) async {
      await pump(tester);
      await tapAndSettle(tester, node('overview:0'));

      await tester.tap(crumb('overview'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      expect(node('topic:a1'), findsOneWidget);
      expect(
        tester
            .widget<Opacity>(
              find.ancestor(
                of: node('topic:a1'),
                matching: find.byType(Opacity),
              ),
            )
            .opacity,
        lessThan(1),
      );

      await tester.pumpAndSettle();
      expect(node('overview:0'), findsOneWidget);
      expect(node('topic:a1'), findsNothing);
    });

    testWidgets('con «sin animaciones», el cambio es directo', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pump(tester);

      await tester.tap(node('overview:0'));
      await tester.pump();
      await tester.pump();
      final first = tester.getCenter(node('topic:a1'));

      expect(
        find.ancestor(of: node('topic:a1'), matching: find.byType(Opacity)),
        findsNothing,
      );
      await tester.pumpAndSettle();
      expect(tester.getCenter(node('topic:a1')), first);
    });
  });

  testWidgets('las uniones se dibujan como una capa compleja y estable, para '
      'que arrastrar no las vuelva a recorrer', (tester) async {
    await pump(tester);

    final layer = tester.widget<CustomPaint>(
      find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is MapEdgesPainter,
      ),
    );

    expect(layer.isComplex, isTrue);
    expect(layer.willChange, isFalse);
  });

  group('F18, 18.2: caché de rasterizado durante el gesto', () {
    testWidgets('durante el gesto se pinta la imagen capturada, no los '
        'nodos', (tester) async {
      await pump(tester);

      viewer(tester).onInteractionStart!(ScaleStartDetails());
      // La captura es asíncrona: deja que se resuelva antes de mirar.
      await tester.pump();
      await tester.pump();

      expect(find.byType(RawImage), findsOneWidget);
      expect(node('overview:0'), findsNothing);
    });

    testWidgets('al soltar, el dibujo vuelve a ser el vectorial de siempre', (
      tester,
    ) async {
      await pump(tester);
      final v = viewer(tester);
      v.onInteractionStart!(ScaleStartDetails());
      await tester.pump();
      await tester.pump();
      expect(find.byType(RawImage), findsOneWidget);

      v.onInteractionEnd!(ScaleEndDetails());
      await tester.pumpAndSettle();

      expect(find.byType(RawImage), findsNothing);
      expect(node('overview:0'), findsOneWidget);
      expect(node('overview:2'), findsOneWidget);
    });

    testWidgets('un arrastre puro no recaptura; un zoom que pasa el doble, '
        'sí', (tester) async {
      await pump(tester);
      final v = viewer(tester);
      final controller = v.transformationController!;
      v.onInteractionStart!(ScaleStartDetails());
      await tester.pump();
      await tester.pump();
      final firstImage = tester.widget<RawImage>(find.byType(RawImage)).image;

      v.onInteractionUpdate!(ScaleUpdateDetails());
      await tester.pump();
      expect(
        identical(
          firstImage,
          tester.widget<RawImage>(find.byType(RawImage)).image,
        ),
        isTrue,
      );

      final now = controller.value.getMaxScaleOnAxis();
      controller.value = Matrix4.diagonal3Values(
        now * 2.5,
        now * 2.5,
        now * 2.5,
      );
      v.onInteractionUpdate!(ScaleUpdateDetails());
      await tester.pump();
      await tester.pump();

      expect(
        identical(
          firstImage,
          tester.widget<RawImage>(find.byType(RawImage)).image,
        ),
        isFalse,
      );
    });
  });

  testWidgets('una fuente y una nota se dibujan distinto, con la forma y el '
      'color de su rol', (tester) async {
    await pump(tester);
    await tapAndSettle(tester, node('overview:0'));
    await tapAndSettle(tester, node('topic:a1'));
    final scheme = Theme.of(tester.element(find.text('Livio'))).colorScheme;

    BoxDecoration decorationOf(String title) =>
        tester
                .widget<DecoratedBox>(
                  find
                      .ancestor(
                        of: find.text(title),
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;

    expect(
      decorationOf('Livio').borderRadius,
      BorderRadius.circular(EntityRole.source.radius),
    );
    expect(
      decorationOf('Mi nota').borderRadius,
      BorderRadius.circular(EntityRole.note.radius),
    );
    expect(decorationOf('Livio').color, EntityRole.source.surface(scheme));
    expect(decorationOf('Mi nota').color, EntityRole.note.surface(scheme));
  });

  group('las etiquetas se leen a cualquier zoom', () {
    void zoom(WidgetTester tester, double scale) {
      viewer(tester).transformationController!.value = Matrix4.diagonal3Values(
        scale,
        scale,
        scale,
      );
    }

    double fontOf(WidgetTester tester, String key, String text) => tester
        .widget<Text>(find.descendant(of: node(key), matching: find.text(text)))
        .style!
        .fontSize!;

    test('a menos zoom, más letra, por escalones', () {
      expect(labelScaleFor(1.2), 1);
      expect(labelScaleFor(0.9), 1);
      expect(labelScaleFor(0.7), 1.5);
      expect(labelScaleFor(0.5), 2.2);
      expect(labelScaleFor(0.35), 3.3);
      expect(labelScaleFor(0.2), 4.5);
    });

    testWidgets('al alejarse, la etiqueta crece; al volver, vuelve', (
      tester,
    ) async {
      await pump(tester);
      await tapAndSettle(tester, node('overview:0'));
      final normal = fontOf(tester, 'topic:a1', 'Alfa 1');

      zoom(tester, 0.4);
      await tester.pump();
      expect(fontOf(tester, 'topic:a1', 'Alfa 1'), greaterThan(normal * 2));

      zoom(tester, 1);
      await tester.pump();
      expect(fontOf(tester, 'topic:a1', 'Alfa 1'), normal);
    });

    testWidgets('muy alejado, la etiqueta de un tema chico se calla', (
      tester,
    ) async {
      await pump(tester, snapshot(isolatedTopics: 3));
      await tapAndSettle(tester, node('overview:2'));
      expect(find.text('Solo 000'), findsOneWidget);

      zoom(tester, 0.25);
      await tester.pump();

      expect(find.text('Solo 000'), findsNothing);
    });
  });

  group('cuando el mapa se recalcula', () {
    testWidgets('se queda a la misma altura, con los mismos nodos casi donde '
        'estaban', (tester) async {
      await pump(tester);
      await tapAndSettle(tester, node('overview:0'));
      final before = tester.getCenter(node('topic:a1'));

      await tester.pumpWidget(app(snapshot(sequence: 2)));
      await tester.pumpAndSettle();

      expect(node('topic:a1'), findsOneWidget);
      // En caliente, sin salto.
      expect(
        (tester.getCenter(node('topic:a1')) - before).distance,
        lessThan(50),
      );
    });

    testWidgets('si lo que se miraba desaparece, vuelve a las comunidades', (
      tester,
    ) async {
      await pump(tester);
      await tapAndSettle(tester, node('overview:1'));
      expect(node('topic:b1'), findsOneWidget);

      await tester.pumpWidget(app(snapshot(sequence: 2, withBeta: false)));
      await tester.pumpAndSettle();

      expect(node('topic:b1'), findsNothing);
      expect(node('overview:0'), findsOneWidget);
    });
  });

  group('los topes', () {
    testWidgets('más temas que los que se dibujan: avisa cuántos faltan', (
      tester,
    ) async {
      // 320 temas sin ninguna unión: las comunidades los juntan en un nodo, y
      // al abrirlo caben 300.
      await pump(tester, snapshot(isolatedTopics: 320));
      await tapAndSettle(tester, node('overview:2'));

      expect(find.byKey(const ValueKey('map-cut')), findsOneWidget);
      expect(find.text(es.mapGraphTopicsCut(300, 320)), findsOneWidget);
    });

    testWidgets('con pocos temas no hay aviso', (tester) async {
      await pump(tester);
      await tapAndSettle(tester, node('overview:0'));

      expect(find.byKey(const ValueKey('map-cut')), findsNothing);
      expect(find.byKey(const ValueKey('map-edges-cut')), findsNothing);
    });

    testWidgets('más uniones que las que se dibujan: se quedan las más '
        'fuertes de cada tema y avisa', (tester) async {
      await pump(tester, snapshot(alfaSize: 12));
      await tapAndSettle(tester, node('overview:0'));

      expect(find.byKey(const ValueKey('map-edges-cut')), findsOneWidget);
      for (var i = 1; i <= 12; i++) {
        expect(node('topic:a$i'), findsOneWidget);
      }
    });
  });

  group('Radial y Árbol: el despliegue nodo a nodo del Esquema', () {
    testWidgets('de lejos, en radial: todo en el centro y las comunidades '
        'alrededor; desplegar una muestra sus temas', (tester) async {
      await pump(tester);
      await arrange(tester, Icons.radar);

      expect(card('all:'), findsOneWidget);
      expect(card('community:0'), findsOneWidget);
      expect(card('community:2'), findsOneWidget);
      expect(card('topic:a1'), findsNothing);
      expect(node('overview:0'), findsNothing);

      await tapAndSettle(tester, card('community:0'));

      for (final id in ['a1', 'a2', 'a3', 'a4']) {
        expect(card('topic:$id'), findsOneWidget);
      }

      // Y plegarla las guarda.
      await tapAndSettle(tester, card('community:0'));
      expect(card('topic:a1'), findsNothing);
    });

    testWidgets('desplegar una rama deja quieto lo que se tocó', (
      tester,
    ) async {
      await pump(tester);
      await arrange(tester, Icons.radar);
      final before = tester.getCenter(card('community:1'));

      await tapAndSettle(tester, card('community:1'));

      expect(
        (tester.getCenter(card('community:1')) - before).distance,
        lessThan(1),
      );
    });

    testWidgets('el botón de una comunidad entra en ella, con sus temas '
        'alrededor de la comunidad', (tester) async {
      await pump(tester);
      await arrange(tester, Icons.radar);

      await tapAndSettle(
        tester,
        find.byKey(const ValueKey('map-tree-open-community:0')),
      );

      expect(crumb('topics'), findsOneWidget);
      expect(card('community:focus'), findsOneWidget);
      expect(card('topic:a1'), findsOneWidget);
      // Sigue en radial.
      expect(node('topic:a1'), findsNothing);
    });

    testWidgets('en un tema, sus notas mapa y sus documentos; desplegar un '
        'documento trae sus vínculos con su tipo', (tester) async {
      repository
        ..links['topic:a1'] = const [
          SchemaLink(
            target: SchemaRef.item('m1'),
            title: 'Mapa de Alfa',
            edge: SchemaEdgeKind.mapNote,
            isNote: true,
          ),
        ]
        ..links['item:i2'] = const [
          SchemaLink(
            target: SchemaRef.item('i3'),
            title: 'Tácito',
            edge: SchemaEdgeKind.relation,
            relation: RelationKind.contradicts,
            outgoing: false,
          ),
        ];
      await pump(tester);
      await tapAndSettle(tester, node('overview:0'));
      await tapAndSettle(tester, node('topic:a1'));

      await arrange(tester, Icons.radar);

      expect(card('topic:a1'), findsOneWidget);
      expect(card('item:m1'), findsOneWidget);
      expect(card('item:i1'), findsOneWidget);
      expect(card('item:i2'), findsOneWidget);
      // Los documentos son los mismos de la red: no se piden de nuevo.
      expect(repository.requested, ['a1']);

      await tapAndSettle(tester, card('item:i2'));

      expect(repository.schemaRequested, contains('item:i2'));
      expect(card('item:i3'), findsOneWidget);
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byWidgetPredicate(
                      (w) =>
                          w is CustomPaint && w.painter is MapTreeEdgesPainter,
                    ),
                  )
                  .painter!
              as MapTreeEdgesPainter;
      final linked = painter.entries.firstWhere((e) => e.key == 'item:i3');
      expect(painter.labelOf(linked), es.relationKindLabelContradicts);
      final note = painter.entries.firstWhere((e) => e.key == 'item:m1');
      expect(painter.labelOf(note), es.mapSchemaEdgeMapNote);
    });

    testWidgets('un nodo sin nada que desplegar se abre al tocarlo, y el botón '
        'de cada uno abre el tema o el documento', (tester) async {
      await pump(tester);
      await tapAndSettle(tester, node('overview:0'));
      await tapAndSettle(tester, node('topic:a1'));
      await arrange(tester, Icons.radar);
      // i1 no tiene vínculos que traer: al pedirlos, viene vacío.
      await tapAndSettle(tester, card('item:i1'));

      await tapAndSettle(tester, card('item:i1'));
      expect(opened, ['item:i1']);

      await tapAndSettle(
        tester,
        find.byKey(const ValueKey('map-tree-open-topic:a1')),
      );
      expect(opened.last, 'topic:a1');
    });

    testWidgets('en árbol, las ramas van de izquierda a derecha', (
      tester,
    ) async {
      await pump(tester);
      await arrange(tester, Icons.account_tree_outlined);

      final root = tester.getCenter(card('all:'));
      final a = tester.getCenter(card('community:0'));
      final b = tester.getCenter(card('community:1'));

      expect(a.dx, greaterThan(root.dx));
      expect(b.dx, closeTo(a.dx, 1));
      expect(b.dy, isNot(closeTo(a.dy, 1)));
    });

    testWidgets('se puede partir de una nota mapa, y volver a lo que se mira', (
      tester,
    ) async {
      repository.mapNotes.add(
        const SchemaLink(
          target: SchemaRef.item('m9'),
          title: 'Mapa de Grecia',
          edge: SchemaEdgeKind.mapNote,
          isNote: true,
        ),
      );
      await pump(tester);
      await arrange(tester, Icons.radar);

      await tapAndSettle(tester, find.byKey(const ValueKey('map-tree-root')));
      await tapAndSettle(
        tester,
        find.byKey(const ValueKey('map-root-note-m9')),
      );

      expect(card('item:m9'), findsOneWidget);
      expect(card('all:'), findsNothing);
      expect(repository.schemaRequested, contains('item:m9'));

      await tapAndSettle(
        tester,
        find.byKey(const ValueKey('map-tree-root-reset')),
      );
      expect(card('all:'), findsOneWidget);
    });

    testWidgets('con demasiados nodos avisa de los que no dibuja', (
      tester,
    ) async {
      await pump(tester, snapshot(isolatedTopics: 320));
      await arrange(tester, Icons.radar);

      await tapAndSettle(tester, card('community:2'));

      expect(find.byKey(const ValueKey('map-tree-truncated')), findsOneWidget);
      expect(card('topic:solo0'), findsOneWidget);
    });

    testWidgets('cada tarjeta se anuncia con lo que es y si está desplegada', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      await arrange(tester, Icons.radar);

      final community = tester.getSemantics(card('community:0'));
      expect(
        community.label,
        es.mapGraphCommunitySemantics('Alfa 1', es.mapTopicCount('spaces', 4)),
      );
      expect(community.hint, es.mapSchemaExpand('Alfa 1'));
      semantics.dispose();
    });
  });

  group('«Ver como lista»', () {
    Finder row(String key) => find.byKey(ValueKey('map-list-row-$key'));
    Finder toggle(String key) => find.byKey(ValueKey('map-list-toggle-$key'));

    testWidgets('las comunidades, que se despliegan en temas y documentos, '
        'con lo que hay que hacer en cada fila', (tester) async {
      await pump(tester);
      await tapAndSettle(tester, find.byKey(const ValueKey('map-as-list')));

      expect(find.byKey(const ValueKey('map-list')), findsOneWidget);
      expect(canvas, findsNothing);
      expect(row('community:0'), findsOneWidget);
      expect(row('topic:a1'), findsNothing);

      await tapAndSettle(tester, toggle('community:0'));
      expect(row('topic:a1'), findsOneWidget);

      await tapAndSettle(tester, toggle('topic:a1'));
      expect(repository.requested, ['a1']);
      expect(row('item:i1'), findsOneWidget);

      await tapAndSettle(
        tester,
        find.byKey(const ValueKey('map-list-open-item:i1')),
      );
      expect(opened, ['item:i1']);
    });

    testWidgets('un vínculo se lee desde el documento de la fila', (
      tester,
    ) async {
      repository.links['item:i2'] = const [
        SchemaLink(
          target: SchemaRef.item('i3'),
          title: 'Tácito',
          edge: SchemaEdgeKind.relation,
          relation: RelationKind.cites,
        ),
      ];
      await pump(tester);
      await tapAndSettle(tester, node('overview:0'));
      await tapAndSettle(tester, node('topic:a1'));
      await tapAndSettle(tester, find.byKey(const ValueKey('map-as-list')));

      await tapAndSettle(tester, toggle('item:i2'));

      // «Mi nota» cita a Tácito: desde Tácito, lo cita «Mi nota».
      expect(
        find.descendant(
          of: row('item:i3'),
          matching: find.text(es.relationKindCitesIncoming('Mi nota')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('«Entrar» en una comunidad baja de altura, y la lista sigue', (
      tester,
    ) async {
      await pump(tester);
      await tapAndSettle(tester, find.byKey(const ValueKey('map-as-list')));

      await tapAndSettle(
        tester,
        find.byKey(const ValueKey('map-list-open-community:1')),
      );

      expect(crumb('topics'), findsOneWidget);
      expect(row('community:focus'), findsOneWidget);
      expect(row('topic:b1'), findsOneWidget);

      // Y se vuelve al dibujo.
      await tapAndSettle(tester, find.byKey(const ValueKey('map-as-list')));
      expect(node('topic:b1'), findsOneWidget);
    });

    testWidgets('el lector de pantalla oye si una fila está desplegada', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      await tapAndSettle(tester, find.byKey(const ValueKey('map-as-list')));

      expect(
        tester.getSemantics(toggle('community:0')),
        isSemantics(
          hasExpandedState: true,
          isExpanded: false,
          isButton: true,
          tooltip: es.mapSchemaExpand('Alfa 1'),
        ),
      );

      await tapAndSettle(tester, toggle('community:0'));
      expect(
        tester.getSemantics(toggle('community:0')),
        isSemantics(hasExpandedState: true, isExpanded: true),
      );
      semantics.dispose();
    });
  });

  group('los documentos vinculados (lo que era la vista «Vínculos»)', () {
    final toggle = find.byKey(const ValueKey('map-links-toggle'));

    testWidgets('se prenden con su botón: lo vinculado tenga o no tema, '
        'cuántos son y cuántos quedan sueltos', (tester) async {
      await pump(tester);

      await tapAndSettle(tester, toggle);

      expect(node('item:a'), findsOneWidget);
      expect(node('item:c'), findsOneWidget);
      expect(node('overview:0'), findsNothing);
      expect(find.text(es.mapLinksSummary(3)), findsOneWidget);
      expect(find.text(es.mapLinksUnlinked(1)), findsOneWidget);
      expect(crumb('links'), findsOneWidget);
      expect(find.byKey(const ValueKey('map-ai-suggest')), findsOneWidget);

      // Apagarlos vuelve a donde se estaba.
      await tapAndSettle(tester, toggle);
      expect(node('overview:0'), findsOneWidget);
    });

    testWidgets('«Más fuertes» pide la mitad que más pesa y lo avisa', (
      tester,
    ) async {
      await pump(tester);
      await tapAndSettle(tester, toggle);
      expect(
        find.byKey(const ValueKey('map-links-strength-cut')),
        findsNothing,
      );

      await tapAndSettle(
        tester,
        find.byKey(const ValueKey('map-links-strength-strongest')),
      );

      expect(linkRequests.last.strength, LinkStrengthFilter.strongest);
      expect(node('item:c'), findsNothing);
      expect(
        find.text(es.mapLinksStrengthCut(1, 2, 'strongest')),
        findsOneWidget,
      );
    });

    testWidgets('«Todo» en las migas apaga los vínculos y vuelve a las '
        'comunidades', (tester) async {
      await pump(tester);
      await tapAndSettle(tester, node('overview:0'));
      await tapAndSettle(tester, toggle);

      await tapAndSettle(tester, crumb('overview'));

      expect(node('overview:0'), findsOneWidget);
      expect(tester.widget<IconButton>(toggle).isSelected, isFalse);
    });

    testWidgets('en radial, todo lo vinculado alrededor, y cada documento con '
        'sus vínculos', (tester) async {
      await pump(tester);
      await tapAndSettle(tester, toggle);

      await arrange(tester, Icons.radar);

      expect(card('links:'), findsOneWidget);
      expect(card('item:a'), findsOneWidget);
      expect(card('item:c'), findsOneWidget);
    });

    testWidgets('sin temas, el lienzo lo dice y lleva a los vínculos', (
      tester,
    ) async {
      await pump(tester, snapshot(empty: true));

      expect(find.byKey(const ValueKey('map-no-topics')), findsOneWidget);
      await tapAndSettle(tester, find.text(es.mapSeeLinksAction));

      expect(node('item:a'), findsOneWidget);
    });
  });

  group('lo que se pide de afuera', () {
    testWidgets('«Ver en el Mapa»: lo vinculado, con el documento resaltado y '
        'encuadrado, y el pedido atendido', (tester) async {
      container.read(mapCanvasRequestProvider.notifier).state =
          const MapShowLinks(focusId: 'b');
      await pump(tester);

      expect(linkRequests.last.focusId, 'b');
      expect(
        tester
            .widget<MapItemBox>(
              find.descendant(
                of: node('item:b'),
                matching: find.byType(MapItemBox),
              ),
            )
            .highlighted,
        isTrue,
      );
      expect(container.read(mapCanvasRequestProvider), isNull);
    });

    testWidgets('un tema: los de su comunidad, con él resaltado', (
      tester,
    ) async {
      await pump(tester);

      container.read(mapCanvasRequestProvider.notifier).state =
          const MapShowTopic('b2');
      await tester.pumpAndSettle();

      expect(crumb('topics'), findsOneWidget);
      expect(
        tester
            .widget<MapNetworkNode>(
              find.descendant(
                of: node('topic:b2'),
                matching: find.byType(MapNetworkNode),
              ),
            )
            .highlighted,
        isTrue,
      );
      expect(container.read(mapCanvasRequestProvider), isNull);
    });

    testWidgets('una altura: todos los temas', (tester) async {
      await pump(tester);

      container.read(mapCanvasRequestProvider.notifier).state =
          const MapShowAltitude(MapAltitude.topics);
      await tester.pumpAndSettle();

      expect(find.text(es.f44S2CrumbAllTopics('spaces')), findsOneWidget);
      expect(node('topic:a1'), findsOneWidget);
      expect(node('topic:b3'), findsOneWidget);
    });
  });

  group('la exportación', () {
    testWidgets('el SVG de las comunidades: un círculo por comunidad, con su '
        'cuenta y su nombre, y dice qué es', (tester) async {
      handle = MapExportHandle();
      await pump(tester);

      final svg = handle!.svg!();

      expect(svg, startsWith('<?xml'));
      expect('<circle'.allMatches(svg), hasLength(3));
      expect(svg, contains('>Alfa 1</text>'));
      expect(svg, contains('>${es.mapBoardIsolatedTitle('spaces')}</text>'));
      expect(handle!.subject!(), (arrangement: 'red', links: false));
    });

    testWidgets('el SVG de los documentos: sus cajas, y los vínculos con su '
        'punta', (tester) async {
      handle = MapExportHandle();
      await pump(tester);
      await tapAndSettle(tester, node('overview:0'));
      await tapAndSettle(tester, node('topic:a1'));

      final svg = handle!.svg!();

      expect(svg, contains('>Livio</text>'));
      expect('<rect'.allMatches(svg), hasLength(2 + 1));
      expect(svg, contains('<polygon'));
    });

    testWidgets('en radial se exporta el árbol, y con los vínculos lo dice', (
      tester,
    ) async {
      handle = MapExportHandle();
      await pump(tester);
      await arrange(tester, Icons.radar);

      expect(handle!.svg!(), contains('>${es.f44S2CrumbAll}</text>'));
      expect(handle!.subject!(), (arrangement: 'radial', links: false));

      await tapAndSettle(
        tester,
        find.byKey(const ValueKey('map-links-toggle')),
      );
      expect(handle!.subject!(), (arrangement: 'radial', links: true));
    });

    testWidgets('el PNG es una imagen de verdad', (tester) async {
      handle = MapExportHandle();
      await pump(tester);

      final bytes = await tester.runAsync(() => handle!.png!());

      expect(bytes!.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    });

    testWidgets('visto como lista no hay dibujo que ofrecer; al irse, '
        'tampoco', (tester) async {
      handle = MapExportHandle();
      await pump(tester);
      expect(handle!.available, isTrue);

      await tapAndSettle(tester, find.byKey(const ValueKey('map-as-list')));
      expect(handle!.available, isFalse);

      await tapAndSettle(tester, find.byKey(const ValueKey('map-as-list')));
      expect(handle!.available, isTrue);

      await tester.pumpWidget(const SizedBox());
      expect(handle!.available, isFalse);
    });
  });

  group('el lector de pantalla', () {
    testWidgets('cada nodo se anuncia con lo que es, y el lienzo ofrece la '
        'lista', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);

      expect(
        tester.getSemantics(node('overview:0')).label,
        es.mapGraphCommunitySemantics('Alfa 1', es.mapTopicCount('spaces', 4)),
      );
      expect(find.bySemanticsLabel(es.f44S2CanvasSemantics(3)), findsOneWidget);
      expect(find.byTooltip(es.f44S2AsList), findsOneWidget);
      expect(find.byTooltip(es.f44S2ZoomIn), findsOneWidget);
      expect(find.byTooltip(es.f44S2Fit), findsOneWidget);

      await tapAndSettle(tester, node('overview:0'));
      expect(
        tester.getSemantics(node('topic:a1')).label,
        contains(es.mapItemCount(12)),
      );
      semantics.dispose();
    });
  });

  group('en el teléfono: 360 dp con la letra al doble', () {
    for (final (name, theme) in [
      ('claro', AppTheme.lightTheme),
      ('oscuro', AppTheme.darkTheme),
    ]) {
      testWidgets('en $name, sin desbordes en la red, los temas, el radial, '
          'los vínculos y la lista', (tester) async {
        tester.view.physicalSize = const Size(360 * 3, 720 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(app(snapshot(), theme: theme, textScale: 2));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tapAndSettle(tester, node('overview:0'));
        expect(tester.takeException(), isNull);
        await tapAndSettle(tester, node('topic:a1'));
        expect(tester.takeException(), isNull);

        await arrange(tester, Icons.radar);
        expect(tester.takeException(), isNull);

        await tapAndSettle(
          tester,
          find.byKey(const ValueKey('map-links-toggle')),
        );
        expect(tester.takeException(), isNull);

        await tapAndSettle(tester, find.byKey(const ValueKey('map-as-list')));
        expect(find.byKey(const ValueKey('map-list')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
