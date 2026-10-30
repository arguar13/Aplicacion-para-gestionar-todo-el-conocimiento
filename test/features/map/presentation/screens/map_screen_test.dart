import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_queue_providers.dart';
import 'package:sinapsis/features/explorer/presentation/providers/explorer_providers.dart';
import 'package:sinapsis/features/explorer/presentation/screens/explorer_screen.dart';
import 'package:sinapsis/features/inbox/presentation/screens/inbox_screen.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/map/presentation/providers/map_canvas_request.dart';
import 'package:sinapsis/features/map/presentation/providers/map_tab_provider.dart';
import 'package:sinapsis/features/map/presentation/screens/map_screen.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/map_canvas_view.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_board_view.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_item_box.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/processed/presentation/screens/processed_document_screen.dart';
import 'package:sinapsis/features/relations/presentation/screens/tension_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/fake_ai_organize_queue.dart';
import '../../../../support/item_rows.dart';
import '../../../../support/library_harness.dart';
import '../../../../support/processed_rows.dart';

/// La pantalla del mapa (F14; F44, paso 2), contra SQLite real y el router
/// real: las dos pestañas —el Resumen con lo que hay en la bóveda y el lienzo
/// único—, adónde lleva cada cosa y que se actualiza solo.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late AppDatabase db;
  late String tema;
  final now = DateTime(2026, 9, 21, 10);

  setUp(() async {
    harness = await LibraryHarness.create();
    db = harness.database;
    tema = await temaDefinitionId(db);
  });

  Future<void> value(String id, String label) => db
      .into(db.propertyValues)
      .insert(
        PropertyValuesCompanion.insert(
          id: id,
          definitionId: tema,
          value: label,
          createdAt: now,
        ),
      );

  Future<void> item(
    String id,
    List<String> values, {
    SourceKind kind = SourceKind.webPage,
  }) async {
    // Un documento procesado: el Mapa se arma con lo procesado (F41, paso 6).
    await insertProcessedDocument(
      db,
      id: id,
      title: 'Fuente $id',
      createdAt: DateTime(2026, 8, 10),
      sourceKind: kind,
    );
    for (final valueId in values) {
      await db
          .into(db.itemPropertyValues)
          .insert(
            ItemPropertyValuesCompanion.insert(
              itemId: id,
              propertyValueId: valueId,
            ),
          );
    }
  }

  var relationCounter = 0;
  Future<void> relate(String from, String to, {RelationKind? kind}) => db
      .into(db.relations)
      .insert(
        RelationsCompanion.insert(
          id: 'r${relationCounter++}',
          fromItemId: from,
          toItemId: to,
          kind: kind ?? RelationKind.contradicts,
          createdAt: now,
        ),
      );

  /// Roma y Grecia comparten dos fuentes; Egipto está solo.
  Future<void> seed() async {
    await value('roma', 'Roma');
    await value('grecia', 'Grecia');
    await value('egipto', 'Egipto');
    await item('s1', ['roma', 'grecia']);
    await item('s2', ['roma', 'grecia']);
    await item('s3', ['roma']);
    await item('s4', ['egipto']);
    await relate('s1', 's2');
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();
    harness.goTo(RoutePaths.graph);
    await tester.pumpAndSettle();
  }

  /// La pestaña del lienzo, en el selector de las dos.
  final mapTab = find.descendant(
    of: find.byKey(const ValueKey('map-tabs')),
    matching: find.text(es.f44S2TabMap),
  );

  Future<void> openMap(WidgetTester tester) async {
    await tester.tap(mapTab);
    await tester.pumpAndSettle();
  }

  Future<void> openSummary(WidgetTester tester) async {
    await tester.tap(find.text(es.f44S2TabSummary));
    await tester.pumpAndSettle();
  }

  Finder node(String key) => find.byKey(ValueKey('map-node-$key'));

  Future<void> arrange(WidgetTester tester, IconData icon) async {
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('map-arrangement')),
        matching: find.byIcon(icon),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sin temas, el Resumen no se tapa: cuenta lo que hay, y el '
      'Mapa dice que todavía no hay temas (F28)', (tester) async {
    await item('suelto', const []);
    await pump(tester);

    expect(find.byType(MapScreen), findsOneWidget);
    expect(find.byType(MapBoardView), findsOneWidget);
    expect(find.text(es.mapTopicCount('tags', 0)), findsOneWidget);

    await openMap(tester);

    expect(find.text(es.mapEmptyTitle('tags')), findsOneWidget);
  });

  group('las dos pestañas (F44, paso 2)', () {
    testWidgets('Resumen y Mapa, y el Resumen la primera vez', (tester) async {
      await seed();
      await pump(tester);

      // Dos, y no cuatro como antes.
      expect(
        tester
            .widget<SegmentedButton<MapTab>>(
              find.byKey(const ValueKey('map-tabs')),
            )
            .segments
            .map((segment) => segment.value),
        [MapTab.summary, MapTab.map],
      );
      expect(find.byType(MapBoardView), findsOneWidget);

      await openMap(tester);

      expect(find.byType(MapCanvasView), findsOneWidget);
      expect(find.byType(MapBoardView), findsNothing);
      expect(node('overview:0'), findsOneWidget);
    });

    testWidgets('la línea de arriba —«Agrupar por» y lo sin ubicar— es una '
        'sola, y está en las dos pestañas', (tester) async {
      await seed();
      await item('suelto', const []);
      await pump(tester);
      // Con lugar de sobra —la letra de las pruebas es más ancha que la de
      // la app—, todo en una fila.
      tester.view.physicalSize = const Size(1600, 3000);
      await tester.pumpAndSettle();
      final category = find.byKey(const ValueKey('map-category'));
      final unassigned = find.byKey(const ValueKey('map-unassigned'));

      expect(category, findsOneWidget);
      expect(unassigned, findsOneWidget);
      // En la misma fila: «Agrupar por» a un lado y lo sin ubicar al otro.
      expect(
        (tester.getCenter(category).dy - tester.getCenter(unassigned).dy).abs(),
        lessThan(12),
      );
      expect(
        tester.getTopLeft(unassigned).dx,
        greaterThan(tester.getTopRight(category).dx),
      );

      await openMap(tester);
      expect(category, findsOneWidget);
      expect(unassigned, findsOneWidget);
    });

    testWidgets('«Ver en el Mapa» desde el Resumen pasa al Mapa, con lo '
        'vinculado a la vista y el foco en el documento', (tester) async {
      await item('a', const []);
      await item('b', const []);
      await relate('a', 'b');
      await pump(tester);
      expect(find.byType(MapBoardView), findsOneWidget);

      harness.container.read(mapCanvasRequestProvider.notifier).state =
          const MapShowLinks(focusId: 'a');
      await tester.pumpAndSettle();

      expect(find.byType(MapCanvasView), findsOneWidget);
      expect(
        tester
            .widget<MapItemBox>(
              find.descendant(
                of: node('item:a'),
                matching: find.byType(MapItemBox),
              ),
            )
            .highlighted,
        isTrue,
      );
      expect(harness.container.read(mapCanvasRequestProvider), isNull);
    });

    for (final (name, dark) in [('claro', false), ('oscuro', true)]) {
      testWidgets('en el teléfono, en $name, con la letra al doble: las '
          'pestañas, la línea de arriba y el lienzo sin desbordes', (
        tester,
      ) async {
        await seed();
        await item('suelto', const []);
        // La última pestaña que se miró fue el Mapa: abre ahí. El Resumen lo
        // rehace el paso 3, con sus propias pruebas en el teléfono.
        await harness.container
            .read(sharedPreferencesProvider)
            .setString('map_last_tab', 'map');
        tester.view.physicalSize = const Size(360 * 3, 720 * 3);
        tester.view.devicePixelRatio = 3;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.platformDispatcher.platformBrightnessTestValue = dark
            ? Brightness.dark
            : Brightness.light;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearAllTestValues);
        await tester.pumpWidget(harness.wrapWithAppRouter());
        await tester.pumpAndSettle();
        harness.goTo(RoutePaths.graph);
        await tester.pumpAndSettle();

        expect(find.byType(MapCanvasView), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(node('overview:0'), findsOneWidget);
        await tester.tap(node('overview:0'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('muestra el tablero de lo que hay en la bóveda', (tester) async {
    await seed();
    await pump(tester);

    // «Mapa» es también la etiqueta de la pestaña: el título es el de la barra.
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(es.mapTitle),
      ),
      findsOneWidget,
    );
    expect(find.text(es.mapTopicCount('tags', 3)), findsOneWidget);
    expect(find.widgetWithText(Chip, es.mapItemCount(4)), findsOneWidget);
    // Roma tiene tres fuentes; Grecia, dos; Egipto, una.
    final roma = tester.getTopLeft(
      find.byKey(const ValueKey('map-densest-roma')),
    );
    final grecia = tester.getTopLeft(
      find.byKey(const ValueKey('map-densest-grecia')),
    );
    expect(roma.dy, lessThan(grecia.dy));
    // Egipto no comparte nada con nadie.
    expect(find.byKey(const ValueKey('map-isolated-egipto')), findsOneWidget);
  });

  testWidgets('las contradicciones abiertas salen con los títulos, y «ver '
      'todas» abre la pantalla de Tensión', (tester) async {
    await seed();
    await pump(tester);

    expect(find.text('Fuente s1  ↔  Fuente s2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('map-contradictions-all')));
    await tester.pumpAndSettle();

    expect(find.byType(TensionScreen), findsOneWidget);
  });

  testWidgets('tocar un tema abre el material de ese tema', (tester) async {
    await seed();
    await pump(tester);

    await tester.tap(find.byKey(const ValueKey('map-densest-roma')));
    await tester.pumpAndSettle();

    expect(find.byType(ExplorerScreen), findsOneWidget);
  });

  testWidgets('en el Mapa, tocar un documento abre su detalle', (tester) async {
    await seed();
    await pump(tester);
    await openMap(tester);
    await tester.tap(node('overview:0'));
    await tester.pumpAndSettle();
    await tester.tap(node('topic:roma'));
    await tester.pumpAndSettle();

    await tester.tap(node('item:s3'));
    await tester.pumpAndSettle();

    // Un documento procesado se abre en su pantalla (F41).
    expect(find.byType(ProcessedDocumentScreen), findsOneWidget);
  });

  testWidgets('se actualiza solo: guardar algo nuevo cambia el tablero', (
    tester,
  ) async {
    await seed();
    await pump(tester);
    expect(find.widgetWithText(Chip, es.mapItemCount(4)), findsOneWidget);

    await tester.runAsync(() => item('s5', ['egipto', 'roma']));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(Chip, es.mapItemCount(5)), findsOneWidget);
    // Egipto ya comparte un elemento con Roma: dejó de estar aislado.
    expect(find.byKey(const ValueKey('map-isolated-egipto')), findsNothing);
  });

  testWidgets('en radial, un tema trae de la base sus notas mapa', (
    tester,
  ) async {
    await seed();
    await insertItemRows(
      db,
      id: 'm1',
      title: 'Mapa de Roma',
      createdAt: DateTime(2026, 8, 12),
      kind: SourceKind.manualNote,
    );
    await (db.update(db.knowledgeNotes)..where((n) => n.itemId.equals('m1')))
        .write(const KnowledgeNotesCompanion(noteKind: Value(NoteKind.map)));
    await db
        .into(db.itemPropertyValues)
        .insert(
          ItemPropertyValuesCompanion.insert(
            itemId: 'm1',
            propertyValueId: 'roma',
          ),
        );
    await pump(tester);
    await openMap(tester);
    await tester.tap(node('overview:0'));
    await tester.pumpAndSettle();
    await tester.tap(node('topic:roma'));
    await tester.pumpAndSettle();

    await arrange(tester, Icons.radar);

    expect(
      find.byKey(const ValueKey('map-tree-node-topic:roma')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('map-tree-node-item:m1')), findsOneWidget);

    // Y volver al Resumen.
    await openSummary(tester);
    expect(find.byType(MapCanvasView), findsNothing);
  });

  group('los documentos vinculados, en el Mapa (F28; F44, paso 2)', () {
    /// Los vínculos se prenden con su botón; sin ningún tema, desde lo que
    /// dice el lienzo vacío.
    Future<void> openLinks(WidgetTester tester) async {
      await openMap(tester);
      final toggle = find.byKey(const ValueKey('map-links-toggle'));
      await tester.tap(
        toggle.evaluate().isEmpty ? find.text(es.mapSeeLinksAction) : toggle,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('dibuja lo vinculado aunque no tenga ningún tema, y cuenta lo '
        'que no tiene vínculos', (tester) async {
      await item('a', const []);
      await item('b', const []);
      await item('suelto', const []);
      await relate('a', 'b', kind: RelationKind.cites);
      await pump(tester);

      await openLinks(tester);

      expect(node('item:a'), findsOneWidget);
      expect(node('item:b'), findsOneWidget);
      expect(node('item:suelto'), findsNothing);
      expect(find.text(es.mapLinksSummary(2)), findsOneWidget);
      expect(find.text(es.mapLinksUnlinked(1)), findsOneWidget);
    });

    testWidgets('vincular dos cosas se ve en el acto', (tester) async {
      await item('a', const []);
      await item('b', const []);
      await item('c', const []);
      await relate('a', 'b');
      await pump(tester);
      await openLinks(tester);
      expect(node('item:c'), findsNothing);

      await tester.runAsync(() => relate('b', 'c'));
      await tester.pumpAndSettle();

      expect(node('item:c'), findsOneWidget);
      expect(find.text(es.mapLinksSummary(3)), findsOneWidget);
    });

    group('los más fuertes, los menos fuertes o todos (F39, paso 8)', () {
      Future<void> seedFour() async {
        for (final id in ['a', 'b', 'c', 'd', 'suelto']) {
          await item(id, const []);
        }
        await relate('a', 'b'); // contradicts: el más fuerte
        await relate('c', 'd', kind: RelationKind.relatedTo);
      }

      bool shows(String id) => node('item:$id').evaluate().isNotEmpty;

      testWidgets('arranca en «Todos» y no avisa nada de un corte', (
        tester,
      ) async {
        await seedFour();
        await pump(tester);

        await openLinks(tester);

        expect(
          tester
              .widget<ChoiceChip>(
                find.widgetWithText(ChoiceChip, es.mapLinksStrengthAll),
              )
              .selected,
          isTrue,
        );
        expect([
          shows('a'),
          shows('b'),
          shows('c'),
          shows('d'),
        ], everyElement(isTrue));
        expect(
          find.byKey(const ValueKey('map-links-strength-cut')),
          findsNothing,
        );
      });

      testWidgets('«Más fuertes» deja la mitad que más pesa y lo avisa; '
          '«Menos fuertes» la otra; «Todos» vuelve', (tester) async {
        await seedFour();
        await pump(tester);
        await openLinks(tester);

        await tester.tap(find.text(es.mapLinksStrengthStrongest));
        await tester.pumpAndSettle();

        expect(
          [shows('a'), shows('b'), shows('c'), shows('d')],
          [true, true, false, false],
        );
        expect(
          find.text(es.mapLinksStrengthCut(1, 2, 'strongest')),
          findsOneWidget,
        );
        // Lo que el corte deja afuera sigue vinculado: solo «suelto» no.
        expect(find.text(es.mapLinksUnlinked(1)), findsOneWidget);

        await tester.tap(find.text(es.mapLinksStrengthWeakest));
        await tester.pumpAndSettle();

        expect(
          [shows('a'), shows('b'), shows('c'), shows('d')],
          [false, false, true, true],
        );
        expect(
          find.text(es.mapLinksStrengthCut(1, 2, 'weakest')),
          findsOneWidget,
        );

        await tester.tap(find.text(es.mapLinksStrengthAll));
        await tester.pumpAndSettle();

        expect([
          shows('a'),
          shows('b'),
          shows('c'),
          shows('d'),
        ], everyElement(isTrue));
        expect(
          find.byKey(const ValueKey('map-links-strength-cut')),
          findsNothing,
        );
      });

      testWidgets('la elección se recuerda cuando llega un vínculo nuevo', (
        tester,
      ) async {
        await seedFour();
        await pump(tester);
        await openLinks(tester);
        await tester.tap(find.text(es.mapLinksStrengthStrongest));
        await tester.pumpAndSettle();

        await tester.runAsync(() => item('e', const []));
        await tester.runAsync(() => relate('c', 'e', kind: RelationKind.cites));
        await tester.pumpAndSettle();

        // Tres vínculos: arriba quedan los dos que más pesan (a-b y c-e).
        expect(
          [shows('a'), shows('c'), shows('e'), shows('d')],
          [true, true, true, false],
        );
        expect(
          tester
              .widget<ChoiceChip>(
                find.widgetWithText(ChoiceChip, es.mapLinksStrengthStrongest),
              )
              .selected,
          isTrue,
        );
      });
    });

    testWidgets('sin vínculos, lo dice y ofrece agregar uno', (tester) async {
      await item('a', const []);
      await pump(tester);

      await openLinks(tester);

      expect(find.text(es.mapLinksEmptyTitle), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, es.graphAddRelationTooltip),
        findsOneWidget,
      );
    });

    testWidgets('tocar un elemento abre su detalle', (tester) async {
      await item('a', const []);
      await item('b', const []);
      await relate('a', 'b');
      await pump(tester);
      await openLinks(tester);

      await tester.tap(node('item:a'));
      await tester.pumpAndSettle();

      expect(find.byType(ProcessedDocumentScreen), findsOneWidget);
    });

    testWidgets('se exporta como SVG con un nombre que dice que son los '
        'vínculos', (tester) async {
      await seed();
      await pump(tester);
      await openLinks(tester);

      await tester.tap(find.byKey(const ValueKey('map-export')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('map-export-svg')));
      await tester.pumpAndSettle();

      expect(harness.fileSaver.savedFileName, 'mapa-red-vinculos.svg');
      final text = String.fromCharCodes(harness.fileSaver.savedBytes!);
      expect(text, contains('Fuente s1'));
    });
  });

  group('los temas (F28)', () {
    Future<String> space(String name, List<String> itemIds) async {
      final created =
          (await harness.container
                  .read(organizeRepositoryProvider)
                  .createSpace(name))
              .getRight()
              .toNullable()!;
      await harness.container
          .read(libraryRepositoryProvider)
          .setSpaces(itemIds: itemIds, spaceIds: {created.id});
      return created.id;
    }

    testWidgets('con temas, el Mapa se arma con ellos por defecto: poner un '
        'tema al guardar ya lo ubica', (tester) async {
      await seed();
      await space('Antigüedad', ['s1', 's2']);
      await space('Egipto antiguo', ['s4']);
      await pump(tester);

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('map-category')),
          matching: find.text(es.topicDimensionSpaces),
        ),
        findsOneWidget,
      );
      expect(find.text(es.mapTopicCount('spaces', 2)), findsOneWidget);
      // s3 no está en ningún tema.
      expect(find.text(es.mapUnassignedSpaces(1)), findsOneWidget);
    });

    testWidgets('tocar un tema abre el Explorador parado en él', (
      tester,
    ) async {
      await seed();
      final antiguedad = await space('Antigüedad', ['s1', 's2']);
      await pump(tester);

      await tester.tap(find.byKey(ValueKey('map-densest-$antiguedad')));
      await tester.pumpAndSettle();

      expect(find.byType(ExplorerScreen), findsOneWidget);
      expect(
        harness.container.read(explorerQueryNotifierProvider).spaceId,
        antiguedad,
      );
    });

    testWidgets('se puede pasar a las etiquetas, y a las demás categorías', (
      tester,
    ) async {
      await seed();
      await space('Antigüedad', ['s1']);
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('map-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.topicDimensionTags).last);
      await tester.pumpAndSettle();

      // Roma, Grecia y Egipto: las etiquetas de la siembra.
      expect(find.text(es.mapTopicCount('tags', 3)), findsOneWidget);
    });

    testWidgets('sin temas, arranca por las etiquetas', (tester) async {
      await seed();
      await pump(tester);

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('map-category')),
          matching: find.text(es.topicDimensionTags),
        ),
        findsOneWidget,
      );
    });
  });

  group('sin vacíos mudos (F28)', () {
    testWidgets('sin etiquetas, el tablero sigue ahí, dice cuántos elementos '
        'quedaron sin ubicar y ofrece organizarlos con la IA', (tester) async {
      final queue = FakeAiOrganizeQueue();
      harness = await LibraryHarness.create(
        extraOverrides: [aiOrganizeQueueProvider.overrideWithValue(queue)],
      );
      db = harness.database;
      await item('a', const []);
      await item('b', const []);
      await pump(tester);

      expect(find.byType(MapBoardView), findsOneWidget);
      expect(find.widgetWithText(Chip, es.mapItemCount(2)), findsOneWidget);
      expect(find.text(es.mapUnassignedTags(2)), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('map-organize-with-ai')));
      await tester.pumpAndSettle();

      expect(queue.organizeNowCalls.toSet(), {'a', 'b'});
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('con todo ubicado, no hay aviso', (tester) async {
      await seed();
      await pump(tester);

      expect(find.byKey(const ValueKey('map-unassigned')), findsNothing);
    });

    testWidgets('el Mapa sin temas lo dice y lleva a los vínculos, que se ven '
        'igual', (tester) async {
      await item('a', const []);
      await item('b', const []);
      await relate('a', 'b');
      await pump(tester);

      await openMap(tester);
      expect(find.byKey(const ValueKey('map-no-topics')), findsOneWidget);

      await tester.tap(find.text(es.mapSeeLinksAction));
      await tester.pumpAndSettle();

      expect(node('item:a'), findsOneWidget);
    });

    testWidgets('vincular dos fuentes desde el detalle avisa, sin prometer un '
        'Mapa en el que no van a estar (F41, paso 6)', (tester) async {
      // «Ver en el Mapa» después de vincular lo ofrece el Mapa mismo, entre
      // documentos procesados (map_graph_relations_test). El detalle de un
      // procesado es su pantalla propia; el de una fuente vincula lo de la
      // Biblioteca, que el Mapa ya no dibuja.
      await insertItemRows(db, id: 'a', title: 'Fuente a');
      await insertItemRows(db, id: 'b', title: 'Fuente b');
      await pump(tester);
      harness.goTo(RoutePaths.itemDetail('a'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(es.detailAddRelation));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Fuente b'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.pickRelationConfirm));
      // El aviso pregunta antes si es un procesado: una consulta de verdad.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(find.text(es.relationLinked), findsOneWidget);
      expect(find.text(es.relationSeeInMap), findsNothing);
      expect(await db.select(db.relations).get(), hasLength(1));
    });
  });

  group('la transición entre pestañas', () {
    testWidgets('es un fundido corto: un instante después de tocar, las dos '
        'pestañas conviven, y al terminar queda solo la nueva', (tester) async {
      await seed();
      await pump(tester);

      await tester.tap(mapTab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.byType(MapBoardView), findsOneWidget);
      expect(find.byType(MapCanvasView), findsOneWidget);

      await tester.pumpAndSettle();

      expect(find.byType(MapBoardView), findsNothing);
      expect(find.byType(MapCanvasView), findsOneWidget);
    });

    testWidgets('si el sistema pide menos movimiento, es inmediata', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await seed();
      await pump(tester);

      await tester.tap(mapTab);
      await tester.pump();
      await tester.pump();

      expect(find.byType(MapBoardView), findsNothing);
      expect(find.byType(MapCanvasView), findsOneWidget);
    });
  });

  group('la exportación', () {
    Future<void> pickExport(WidgetTester tester, String key) async {
      await tester.tap(find.byKey(const ValueKey('map-export')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(key)));
      // El PNG se pinta de verdad, y eso no avanza con el reloj simulado.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('en el Resumen no hay nada que exportar: el botón está '
        'apagado y dice por qué', (tester) async {
      await seed();
      await pump(tester);

      final button = tester.widget<PopupMenuButton<String>>(
        find.byKey(const ValueKey('map-export')),
      );

      expect(button.enabled, isFalse);
      expect(button.tooltip, es.mapExportUnavailable);
    });

    testWidgets('en radial guarda un SVG con el nombre de la disposición y la '
        'categoría', (tester) async {
      await seed();
      await pump(tester);
      await openMap(tester);
      await arrange(tester, Icons.radar);

      await pickExport(tester, 'map-export-svg');

      expect(harness.fileSaver.savedFileName, 'mapa-radial-etiquetas.svg');
      final text = String.fromCharCodes(harness.fileSaver.savedBytes!);
      expect(text, startsWith('<?xml'));
      // De lejos, en radial: «Todo» en el centro y las comunidades alrededor.
      expect(text, contains('>${es.f44S2CrumbAll}</text>'));
      expect(text, contains('>${es.mapBoardIsolatedTitle('tags')}</text>'));
      expect(find.text(es.mapExportSaved), findsOneWidget);
    });

    testWidgets('en la red guarda un PNG', (tester) async {
      await seed();
      await pump(tester);
      await openMap(tester);

      await pickExport(tester, 'map-export-png');

      expect(harness.fileSaver.savedFileName, 'mapa-red-etiquetas.png');
      expect(harness.fileSaver.savedBytes!.sublist(0, 8), [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ]);
    });

    testWidgets('si guardar falla, lo dice', (tester) async {
      await seed();
      await pump(tester);
      await openMap(tester);
      harness.fileSaver.error = StateError('disco lleno');

      await pickExport(tester, 'map-export-svg');

      expect(find.text(es.mapExportSaved), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('visto como lista no hay dibujo que guardar, y lo dice', (
      tester,
    ) async {
      await seed();
      await pump(tester);
      await openMap(tester);
      await tester.tap(find.byKey(const ValueKey('map-as-list')));
      await tester.pumpAndSettle();

      await pickExport(tester, 'map-export-svg');

      expect(find.text(es.f44S2ExportFromList), findsOneWidget);
      expect(harness.fileSaver.savedFileName, isNull);
    });
  });

  group('los filtros', () {
    Future<void> openFilters(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('map-filters')));
      await tester.pumpAndSettle();
    }

    Future<void> closeSheet(WidgetTester tester) async {
      // Un toque en la barrera, fuera del panel.
      await tester.tapAt(const Offset(500, 20));
      await tester.pumpAndSettle();
    }

    testWidgets('filtrar por tipo cambia lo que cuenta el mapa, y el aviso lo '
        'dice', (tester) async {
      await seed();
      await item('d1', ['roma'], kind: SourceKind.document);
      await pump(tester);
      expect(find.widgetWithText(Chip, es.mapItemCount(5)), findsOneWidget);
      expect(find.byKey(const ValueKey('map-filter-active')), findsNothing);

      await openFilters(tester);
      await tester.tap(find.byKey(const ValueKey('map-filter-kind-document')));
      await tester.pumpAndSettle();
      await closeSheet(tester);

      expect(find.widgetWithText(Chip, es.mapItemCount(1)), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('map-filter-active')),
          matching: find.text(es.mapFilterActive(1)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('filtrar por un tema de la biblioteca deja solo sus '
        'elementos, y tocarlo otra vez lo quita', (tester) async {
      await seed();
      final space =
          (await harness.container
                  .read(organizeRepositoryProvider)
                  .createSpace('Antigüedad'))
              .getRight()
              .toNullable()!;
      await harness.container
          .read(libraryRepositoryProvider)
          .setSpaces(itemIds: ['s1', 's4'], spaceIds: {space.id});
      await pump(tester);
      expect(find.widgetWithText(Chip, es.mapItemCount(4)), findsOneWidget);
      final chip = find.byKey(ValueKey('map-filter-space-${space.id}'));

      await openFilters(tester);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      await closeSheet(tester);

      expect(find.widgetWithText(Chip, es.mapItemCount(2)), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('map-filter-active')),
          matching: find.text(es.mapFilterActive(1)),
        ),
        findsOneWidget,
      );

      await openFilters(tester);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      await closeSheet(tester);

      expect(find.byKey(const ValueKey('map-filter-active')), findsNothing);
      expect(find.widgetWithText(Chip, es.mapItemCount(4)), findsOneWidget);
    });

    testWidgets('quitar el filtro desde el aviso devuelve todo', (
      tester,
    ) async {
      await seed();
      await item('d1', ['roma'], kind: SourceKind.document);
      await pump(tester);
      await openFilters(tester);
      await tester.tap(find.byKey(const ValueKey('map-filter-kind-document')));
      await tester.pumpAndSettle();
      await closeSheet(tester);

      await tester.tap(find.byTooltip(es.mapFilterClear));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('map-filter-active')), findsNothing);
      expect(find.widgetWithText(Chip, es.mapItemCount(5)), findsOneWidget);
    });

    testWidgets('el filtro rige a las dos pestañas: sigue puesto al cambiar de '
        'una a otra', (tester) async {
      await seed();
      await item('d1', ['roma'], kind: SourceKind.document);
      await pump(tester);
      await openFilters(tester);
      await tester.tap(find.byKey(const ValueKey('map-filter-kind-document')));
      await tester.pumpAndSettle();
      await closeSheet(tester);

      await openMap(tester);
      expect(find.byKey(const ValueKey('map-filter-active')), findsOneWidget);

      await openSummary(tester);
      expect(find.byKey(const ValueKey('map-filter-active')), findsOneWidget);
    });

    testWidgets('el panel: «quitar filtros» aparece con algún filtro y los '
        'saca', (tester) async {
      await seed();
      await pump(tester);
      await openFilters(tester);
      expect(find.byKey(const ValueKey('map-filter-clear')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('map-filter-kind-webPage')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('map-filter-clear')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('map-filter-clear')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('map-filter-clear')), findsNothing);
    });
  });

  testWidgets('cuánto se trabajó lo procesado sale del tablero (F41)', (
    tester,
  ) async {
    await seed();
    await insertProcessedDocument(
      db,
      id: 'n1',
      title: 'Con notas',
      createdAt: DateTime(2026, 8, 12),
      sections: {ProcessedSection.notes},
    );
    await pump(tester);

    expect(find.text('${es.processedDepthAnnotated}: 1'), findsOneWidget);
  });

  testWidgets('sin nada procesado explica que se llena al triar, y lleva a la '
      'Bandeja; lo de la Biblioteca no cuenta (F41, paso 6)', (tester) async {
    await insertItemRows(db, id: 'fuente', title: 'Fuente');
    await pump(tester);

    expect(find.byKey(const ValueKey('fills-on-triage')), findsOneWidget);
    expect(find.text(es.mapFillsOnTriageTitle), findsOneWidget);
    expect(find.byType(MapBoardView), findsNothing);

    await tester.tap(find.text(es.organizedGoToInbox));
    await tester.pumpAndSettle();
    expect(find.byType(InboxScreen), findsOneWidget);
  });
}
