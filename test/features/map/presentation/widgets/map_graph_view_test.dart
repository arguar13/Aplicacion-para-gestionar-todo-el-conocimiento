import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/atlas/domain/services/atlas_builder.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/knowledge_map_state.dart';
import 'package:sinapsis/features/map/domain/entities/map_dashboard.dart';
import 'package:sinapsis/features/map/domain/entities/schema.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/entities/topic_items.dart';
import 'package:sinapsis/features/map/domain/repositories/knowledge_map_repository.dart';
import 'package:sinapsis/features/map/domain/services/knowledge_map_engine.dart';
import 'package:sinapsis/features/map/presentation/providers/map_layout_runner.dart';
import 'package:sinapsis/features/map/presentation/providers/map_providers.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_edges_painter.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_export_handle.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_graph_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// Un repositorio a mano: lo único que el grafo le pide es lo que tiene un
/// tema.
class _FakeRepository implements KnowledgeMapRepository {
  final requested = <String>[];

  @override
  Future<TopicItemsGraph> readTopicItems(
    String valueId, {
    int limit = kMaxGraphItems,
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
  Future<TopicGraphInput> readTopicInput(
    String definitionId, {
    LibraryQuery filter = const LibraryQuery(),
  }) => throw UnimplementedError();

  @override
  Future<MapDashboard> readDashboard({
    LibraryQuery filter = const LibraryQuery(),
  }) => throw UnimplementedError();

  @override
  Future<List<SchemaLink>> readMapNotes({int limit = kMaxMapNotes}) =>
      throw UnimplementedError();

  @override
  Future<List<SchemaLink>> schemaLinks(
    SchemaRef node, {
    int limit = kSchemaFanOut,
  }) => throw UnimplementedError();

  @override
  Stream<void> changes({LibraryQuery filter = const LibraryQuery()}) =>
      const Stream.empty();
}

/// El grafo de conocimiento (F14, D5) como widget: comunidades, temas y
/// elementos, y cómo se pasa de un nivel a otro.
void main() {
  final es = AppLocalizationsEs();
  late _FakeRepository repository;
  final opened = <String>[];

  /// Dos comunidades de temas muy unidos entre sí —Alfa, de [alfaSize], y
  /// Beta, de cuatro— con un vínculo entre las dos, y un tema aislado.
  KnowledgeMapSnapshot snapshot({
    int sequence = 1,
    bool withBeta = true,
    int isolatedTopics = 1,
    int alfaSize = 4,
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
      values: [
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
      items: items,
      relations: [
        if (withBeta)
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

  MapExportHandle? handle;

  Widget app(KnowledgeMapSnapshot map) => ProviderScope(
    overrides: [
      knowledgeMapRepositoryProvider.overrideWithValue(repository),
      mapLayoutRunnerProvider.overrideWithValue((job) async => runLayout(job)),
    ],
    child: MaterialApp(
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MapGraphView(
          snapshot: map,
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

  Finder node(String key) => find.byKey(ValueKey('map-graph-node-$key'));
  Finder crumb(String level) => find.byKey(ValueKey('map-graph-crumb-$level'));

  setUp(() {
    repository = _FakeRepository();
    opened.clear();
    handle = null;
  });

  test('los datos de las pruebas dan dos comunidades y un aislado', () {
    final map = snapshot();

    final connected = map.detection.communities.where((c) => !c.isIsolated);
    expect(connected, hasLength(2));
    expect(connected.every((c) => c.members.length == 4), isTrue);
    expect(map.detection.communities.where((c) => c.isIsolated), hasLength(1));
  });

  testWidgets('el panorama: un nodo por comunidad y uno para los aislados', (
    tester,
  ) async {
    await pump(tester);

    expect(node('overview:0'), findsOneWidget);
    expect(node('overview:1'), findsOneWidget);
    expect(node('overview:2'), findsOneWidget);
    expect(find.text(es.mapGraphHint), findsOneWidget);
    expect(crumb('overview'), findsOneWidget);
    expect(crumb('topics'), findsNothing);
    // El nodo de los aislados se rotula solo.
    expect(find.text(es.mapBoardIsolatedTitle), findsOneWidget);
  });

  testWidgets('tocar una comunidad muestra sus temas, y el camino vuelve', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(node('overview:0'));
    await tester.pumpAndSettle();

    for (final id in ['a1', 'a2', 'a3', 'a4']) {
      expect(node('topic:$id'), findsOneWidget);
    }
    // Beta se une a Alfa por un vínculo: sus temas vecinos entran, el resto no.
    expect(node('topic:b1'), findsOneWidget);
    expect(node('topic:b3'), findsNothing);
    expect(node('overview:0'), findsNothing);
    expect(crumb('topics'), findsOneWidget);

    await tester.tap(crumb('overview'));
    await tester.pumpAndSettle();

    expect(node('overview:0'), findsOneWidget);
    expect(node('topic:a1'), findsNothing);
  });

  testWidgets('tocar un tema ofrece sus elementos y su material', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(node('overview:0'));
    await tester.pumpAndSettle();

    await tester.tap(node('topic:a1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('map-graph-action-items')));
    await tester.pumpAndSettle();

    expect(repository.requested, ['a1']);
    expect(node('item:i1'), findsOneWidget);
    expect(node('item:i2'), findsOneWidget);
    expect(crumb('items'), findsOneWidget);

    await tester.tap(node('item:i1'));
    expect(opened, ['item:i1']);
  });

  testWidgets('«ver el material» abre el tema', (tester) async {
    await pump(tester);
    await tester.tap(node('overview:0'));
    await tester.pumpAndSettle();

    await tester.tap(node('topic:a2'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('map-graph-action-material')));
    await tester.pumpAndSettle();

    expect(opened, ['topic:a2']);
  });

  testWidgets('desde los elementos, el camino vuelve a los temas', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(node('overview:0'));
    await tester.pumpAndSettle();
    await tester.tap(node('topic:a1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('map-graph-action-items')));
    await tester.pumpAndSettle();

    await tester.tap(crumb('topics'));
    await tester.pumpAndSettle();

    expect(node('topic:a1'), findsOneWidget);
    expect(node('item:i1'), findsNothing);
  });

  group('con el zoom', () {
    void zoom(WidgetTester tester, double scale) {
      final viewer = tester.widget<InteractiveViewer>(
        find.byKey(const ValueKey('map-graph-canvas')),
      );
      viewer.transformationController!.value = Matrix4.diagonal3Values(
        scale,
        scale,
        scale,
      );
      viewer.onInteractionEnd!(ScaleEndDetails());
    }

    testWidgets('acercarse mucho pasa a los temas del nodo del centro', (
      tester,
    ) async {
      await pump(tester);

      zoom(tester, kZoomInThreshold + 0.5);
      await tester.pumpAndSettle();

      expect(crumb('overview'), findsOneWidget);
      expect(node('overview:0'), findsNothing);
      // Alguna comunidad se abrió: hay temas y no hay panorama.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith(
                'map-graph-node-topic:',
              ),
        ),
        findsWidgets,
      );
    });

    testWidgets('un zoom moderado no cambia de nivel', (tester) async {
      await pump(tester);
      final fit = tester
          .widget<InteractiveViewer>(
            find.byKey(const ValueKey('map-graph-canvas')),
          )
          .transformationController!
          .value
          .getMaxScaleOnAxis();

      // Una vez y media el encuadre: lejos de tres veces.
      zoom(tester, fit * 1.5);
      await tester.pumpAndSettle();

      expect(node('overview:0'), findsOneWidget);
    });

    testWidgets('alejarse mucho vuelve al nivel anterior', (tester) async {
      await pump(tester);
      await tester.tap(node('overview:0'));
      await tester.pumpAndSettle();
      expect(node('topic:a1'), findsOneWidget);

      zoom(tester, kZoomOutThreshold - 0.1);
      await tester.pumpAndSettle();

      expect(node('overview:0'), findsOneWidget);
      expect(node('topic:a1'), findsNothing);
    });

    group('con el nivel encuadrado muy alejado', () {
      // Un celular angosto: los temas de una comunidad quedan encuadrados
      // por debajo del umbral de alejamiento.
      const narrow = Size(120, 420);
      final canvas = find.byKey(const ValueKey('map-graph-canvas'));

      InteractiveViewer viewer(WidgetTester tester) =>
          tester.widget<InteractiveViewer>(canvas);

      double scaleOf(WidgetTester tester) =>
          viewer(tester).transformationController!.value.getMaxScaleOnAxis();

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

      testWidgets('arrastrar el mapa no lo saca del nivel', (tester) async {
        await openAlfaTopics(tester);

        gesture(tester, pan: const Offset(-30, -20));
        await tester.pumpAndSettle();
        gesture(tester, scale: 1.02, pan: const Offset(20, 10));
        await tester.pumpAndSettle();

        expect(node('topic:a1'), findsOneWidget);
        expect(node('overview:0'), findsNothing);
      });

      testWidgets('alejarse un poco más sí vuelve al nivel anterior', (
        tester,
      ) async {
        await openAlfaTopics(tester);

        gesture(tester, scale: 0.8);
        await tester.pumpAndSettle();

        expect(node('overview:0'), findsOneWidget);
        expect(node('topic:a1'), findsNothing);
      });

      testWidgets('acercarse a tres veces el encuadre pasa al siguiente nivel '
          'sin llegar al umbral absoluto', (tester) async {
        await openAlfaTopics(tester);
        final fit = scaleOf(tester);
        expect(fit * kZoomInFromFit, lessThan(kZoomInThreshold));

        gesture(tester, scale: kZoomInFromFit + 0.5);
        await tester.pumpAndSettle();

        expect(node('topic:a1'), findsNothing);
        expect(node('item:i1'), findsOneWidget);
      });

      testWidgets('acercarse menos que eso no cambia de nivel', (tester) async {
        await openAlfaTopics(tester);

        gesture(tester, scale: 2);
        await tester.pumpAndSettle();

        expect(node('topic:a1'), findsOneWidget);
      });
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
    InteractiveViewer viewer(WidgetTester tester) =>
        tester.widget(find.byKey(const ValueKey('map-graph-canvas')));

    testWidgets('durante el gesto se pinta la imagen capturada, no los '
        'nodos', (tester) async {
      await pump(tester);
      expect(node('overview:0'), findsOneWidget);

      viewer(tester).onInteractionStart!(ScaleStartDetails());
      // La captura es asíncrona: deja que se resuelva antes de mirar.
      await tester.pump();
      await tester.pump();

      expect(find.byType(RawImage), findsOneWidget);
      expect(node('overview:0'), findsNothing);
    });

    testWidgets('al soltar, el dibujo vuelve a ser el vectorial de siempre, '
        'idéntico al de antes del gesto', (tester) async {
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
      expect(node('overview:1'), findsOneWidget);
      expect(node('overview:2'), findsOneWidget);
    });

    testWidgets('un arrastre puro no cambia el zoom, así que no recaptura '
        'nada a mitad de camino', (tester) async {
      await pump(tester);

      final v = viewer(tester);
      v.onInteractionStart!(ScaleStartDetails());
      await tester.pump();
      await tester.pump();
      final firstImage = tester.widget<RawImage>(find.byType(RawImage)).image;

      // Un arrastre no toca la escala del controlador.
      v.onInteractionUpdate!(ScaleUpdateDetails());
      await tester.pump();

      final stillSame = tester.widget<RawImage>(find.byType(RawImage)).image;
      expect(identical(firstImage, stillSame), isTrue);
    });

    testWidgets('un zoom que pasa el doble desde la captura recaptura a '
        'mitad del gesto', (tester) async {
      await pump(tester);

      final v = viewer(tester);
      final controller = v.transformationController!;
      v.onInteractionStart!(ScaleStartDetails());
      await tester.pump();
      await tester.pump();
      final firstImage = tester.widget<RawImage>(find.byType(RawImage)).image;

      final now = controller.value.getMaxScaleOnAxis();
      controller.value = Matrix4.diagonal3Values(
        now * 2.5,
        now * 2.5,
        now * 2.5,
      );
      v.onInteractionUpdate!(ScaleUpdateDetails());
      await tester.pump();
      await tester.pump();

      final recaptured = tester.widget<RawImage>(find.byType(RawImage)).image;
      expect(identical(firstImage, recaptured), isFalse);
    });
  });

  group('fuente y nota', () {
    testWidgets('se dibujan distinto, con la forma y el color de su rol', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(node('overview:0'));
      await tester.pumpAndSettle();
      await tester.tap(node('topic:a1'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('map-graph-action-items')));
      await tester.pumpAndSettle();
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
      expect(decorationOf('Livio').color, isNot(decorationOf('Mi nota').color));
    });
  });

  group('la exportación', () {
    testWidgets('el SVG del panorama: un círculo por comunidad, con su cuenta '
        'y su nombre', (tester) async {
      handle = MapExportHandle();
      await pump(tester);

      final svg = handle!.svg!();

      expect(svg, startsWith('<?xml'));
      // Dos comunidades y los aislados, más la unión débil entre las dos.
      expect('<circle'.allMatches(svg), hasLength(3));
      expect(svg, contains('>Alfa 1</text>'));
      expect(svg, contains('>Beta 1</text>'));
      expect(svg, contains('>${es.mapBoardIsolatedTitle}</text>'));
      expect('<line'.allMatches(svg), hasLength(1));
    });

    testWidgets('el SVG de los elementos: notas y fuentes con su título, y los '
        'vínculos con su punta', (tester) async {
      handle = MapExportHandle();
      await pump(tester);
      await tester.tap(node('overview:0'));
      await tester.pumpAndSettle();
      await tester.tap(node('topic:a1'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('map-graph-action-items')));
      await tester.pumpAndSettle();

      final svg = handle!.svg!();

      expect(svg, contains('>Livio</text>'));
      expect(svg, contains('>Mi nota</text>'));
      // Dos tarjetas más el fondo; una unión con su punta.
      expect('<rect'.allMatches(svg), hasLength(2 + 1));
      expect(svg, contains('<polygon'));
    });

    testWidgets('el PNG es una imagen de verdad', (tester) async {
      handle = MapExportHandle();
      await pump(tester);

      final bytes = await tester.runAsync(() => handle!.png!());

      expect(bytes, isNotNull);
      expect(bytes!.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    });

    testWidgets('sin vista que exportar, no hay nada que ofrecer', (
      tester,
    ) async {
      handle = MapExportHandle();
      await pump(tester);
      await tester.pumpWidget(const SizedBox());

      expect(handle!.available, isFalse);
    });
  });

  group('las etiquetas se leen a cualquier zoom', () {
    void zoom(WidgetTester tester, double scale) {
      final viewer = tester.widget<InteractiveViewer>(
        find.byKey(const ValueKey('map-graph-canvas')),
      );
      viewer.transformationController!.value = Matrix4.diagonal3Values(
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
      await tester.tap(node('overview:0'));
      await tester.pumpAndSettle();
      final normal = fontOf(tester, 'topic:a1', 'Alfa 1');

      zoom(tester, 0.4);
      await tester.pump();
      final far = fontOf(tester, 'topic:a1', 'Alfa 1');
      expect(far, greaterThan(normal * 2));

      zoom(tester, 1);
      await tester.pump();
      expect(fontOf(tester, 'topic:a1', 'Alfa 1'), normal);
    });

    testWidgets('muy alejado, la etiqueta de un tema chico se calla y la de '
        'los grandes no', (tester) async {
      // Tres temas aislados sin elementos —círculos chicos— y dos comunidades
      // de temas grandes.
      await pump(tester, snapshot(isolatedTopics: 3));
      await tester.tap(node('overview:2'));
      await tester.pumpAndSettle();
      expect(find.text('Solo 000'), findsOneWidget);

      zoom(tester, 0.25);
      await tester.pump();

      expect(find.text('Solo 000'), findsNothing);
    });
  });

  group('cuando el mapa se recalcula', () {
    testWidgets('se queda en el mismo nivel, con los mismos nodos casi donde '
        'estaban', (tester) async {
      await pump(tester);
      await tester.tap(node('overview:0'));
      await tester.pumpAndSettle();
      final before = tester.getCenter(node('topic:a1'));
      final beforeOther = tester.getCenter(node('topic:a4'));

      await tester.pumpWidget(app(snapshot(sequence: 2)));
      await tester.pumpAndSettle();

      expect(node('topic:a1'), findsOneWidget);
      // En caliente, sin salto: el mismo lugar con lo poco que se acomodó.
      expect(
        (tester.getCenter(node('topic:a1')) - before).distance,
        lessThan(50),
      );
      expect(
        (tester.getCenter(node('topic:a4')) - beforeOther).distance,
        lessThan(50),
      );
    });

    testWidgets('si lo que se miraba desaparece, vuelve al panorama', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(node('overview:1'));
      await tester.pumpAndSettle();
      expect(node('topic:b1'), findsOneWidget);

      await tester.pumpWidget(app(snapshot(sequence: 2, withBeta: false)));
      await tester.pumpAndSettle();

      expect(node('topic:b1'), findsNothing);
      expect(node('overview:0'), findsOneWidget);
    });
  });

  testWidgets('más temas que los que se dibujan: avisa cuántos faltan', (
    tester,
  ) async {
    // 320 temas sin ninguna unión: el panorama los junta en un nodo, y al
    // abrirlo caben 300.
    await pump(tester, snapshot(isolatedTopics: 320));
    await tester.tap(node('overview:2'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('map-graph-cut')), findsOneWidget);
    expect(find.text(es.mapGraphTopicsCut(300, 320)), findsOneWidget);
  });

  testWidgets('con pocos temas no hay aviso', (tester) async {
    await pump(tester);
    await tester.tap(node('overview:0'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('map-graph-cut')), findsNothing);
    expect(find.byKey(const ValueKey('map-graph-edges-cut')), findsNothing);
  });

  testWidgets('más uniones que las que se dibujan: se quedan las más fuertes '
      'de cada tema y avisa', (tester) async {
    // Doce temas todos unidos con todos: 66 uniones y unas pocas más con sus
    // vecinos, y a lo sumo cuatro por tema.
    await pump(tester, snapshot(alfaSize: 12));
    await tester.tap(node('overview:0'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('map-graph-edges-cut')), findsOneWidget);
    expect(find.textContaining('uniones más fuertes de'), findsOneWidget);
    // Los doce temas siguen todos a la vista: solo se callan uniones.
    for (var i = 1; i <= 12; i++) {
      expect(node('topic:a$i'), findsOneWidget);
    }
  });

  testWidgets('cada nodo se anuncia con lo que es', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    expect(
      tester.getSemantics(node('overview:0')).label,
      startsWith(es.mapGraphCommunitySemantics('Alfa 1', 4).split(':').first),
    );
    await tester.tap(node('overview:0'));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(node('topic:a1')).label,
      contains(es.mapItemCount(12)),
    );
    handle.dispose();
  });
}
