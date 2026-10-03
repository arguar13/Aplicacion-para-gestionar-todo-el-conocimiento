import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_queue_providers.dart';
import 'package:sinapsis/features/explorer/presentation/providers/explorer_providers.dart';
import 'package:sinapsis/features/explorer/presentation/screens/explorer_screen.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/features/map/presentation/screens/map_screen.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_board_view.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_item_box.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_schema_view.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/relations/presentation/screens/tension_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/fake_ai_organize_queue.dart';
import '../../../../support/item_rows.dart';
import '../../../../support/library_harness.dart';

/// La pantalla del mapa (F14), contra SQLite real y el router real: el tablero
/// con lo que hay en la bóveda, adónde lleva cada cosa y que se actualiza solo.
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
    await insertItemRows(
      db,
      id: id,
      title: 'Fuente $id',
      createdAt: DateTime(2026, 8, 10),
      kind: kind,
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

  testWidgets('sin temas, el tablero no se tapa: cuenta lo que hay, y el '
      'esquema dice que todavía no hay temas (F28)', (tester) async {
    await pump(tester);

    expect(find.byType(MapScreen), findsOneWidget);
    expect(find.byType(MapBoardView), findsOneWidget);
    expect(find.text(es.mapTopicCount(0)), findsOneWidget);

    await tester.tap(find.text(es.mapViewSchema));
    await tester.pumpAndSettle();

    expect(find.text(es.mapEmptyTitle), findsOneWidget);
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
    expect(find.text(es.mapTopicCount(3)), findsOneWidget);
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

  testWidgets('en el grafo, tocar un elemento abre su detalle', (tester) async {
    await seed();
    await pump(tester);
    await tester.tap(find.text(es.mapViewGraph));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('map-graph-node-overview:0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('map-graph-node-topic:roma')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('map-graph-action-items')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('map-graph-node-item:s3')));
    await tester.pumpAndSettle();

    expect(find.byType(ItemDetailScreen), findsOneWidget);
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

  testWidgets('el selector cambia al esquema, que parte del tema con más '
      'material y trae de la base sus notas mapa', (tester) async {
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
    expect(find.byType(MapSchemaView), findsNothing);

    await tester.tap(find.text(es.mapViewSchema));
    await tester.pumpAndSettle();

    expect(find.byType(MapSchemaView), findsOneWidget);
    expect(
      find.byKey(const ValueKey('map-schema-node-topic:roma')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('map-schema-node-item:m1')),
      findsOneWidget,
    );

    // Y volver al tablero.
    await tester.tap(find.text(es.mapViewBoard));
    await tester.pumpAndSettle();
    expect(find.byType(MapSchemaView), findsNothing);
  });

  group('la vista «Vínculos» (F28)', () {
    Future<void> openLinks(WidgetTester tester) async {
      await tester.tap(find.text(es.mapViewLinks));
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

      expect(find.byKey(const ValueKey('map-links-node-a')), findsOneWidget);
      expect(find.byKey(const ValueKey('map-links-node-b')), findsOneWidget);
      expect(find.byKey(const ValueKey('map-links-node-suelto')), findsNothing);
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
      expect(find.byKey(const ValueKey('map-links-node-c')), findsNothing);

      await tester.runAsync(() => relate('b', 'c'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('map-links-node-c')), findsOneWidget);
      expect(find.text(es.mapLinksSummary(3)), findsOneWidget);
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

      await tester.tap(find.byKey(const ValueKey('map-links-node-a')));
      await tester.pumpAndSettle();

      expect(find.byType(ItemDetailScreen), findsOneWidget);
    });

    testWidgets('se exporta como SVG con el nombre de la vista', (
      tester,
    ) async {
      await seed();
      await pump(tester);
      await openLinks(tester);

      await tester.tap(find.byKey(const ValueKey('map-export')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('map-export-svg')));
      await tester.pumpAndSettle();

      expect(harness.fileSaver.savedFileName, 'mapa-vinculos.svg');
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
          .assignSpaceMany(itemIds: itemIds, spaceId: created.id);
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
      expect(find.text(es.mapTopicCount(2)), findsOneWidget);
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
      expect(find.text(es.mapTopicCount(3)), findsOneWidget);
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

    testWidgets('el esquema y el grafo sin temas lo dicen y llevan a los '
        'vínculos, que se ven igual', (tester) async {
      await item('a', const []);
      await item('b', const []);
      await relate('a', 'b');
      await pump(tester);

      for (final view in [es.mapViewSchema, es.mapViewGraph]) {
        await tester.tap(find.text(view));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('map-no-topics')), findsOneWidget);
      }

      await tester.tap(find.text(es.mapSeeLinksAction));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('map-links-node-a')), findsOneWidget);
    });

    testWidgets('vincular desde el detalle avisa, y «Ver en el Mapa» abre los '
        'vínculos con el foco en ese elemento', (tester) async {
      await item('a', const []);
      await item('b', const []);
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
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.relationSeeInMap));
      await tester.pumpAndSettle();

      expect(find.byType(MapScreen), findsOneWidget);
      final a = find.descendant(
        of: find.byKey(const ValueKey('map-links-node-a')),
        matching: find.byType(MapItemBox),
      );
      expect(tester.widget<MapItemBox>(a).highlighted, isTrue);
    });
  });

  group('la transición entre vistas', () {
    testWidgets('es un fundido corto: un instante después de tocar, las dos '
        'vistas conviven, y al terminar queda solo la nueva', (tester) async {
      await seed();
      await pump(tester);

      await tester.tap(find.text(es.mapViewSchema));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.byType(MapBoardView), findsOneWidget);
      expect(find.byType(MapSchemaView), findsOneWidget);

      await tester.pumpAndSettle();

      expect(find.byType(MapBoardView), findsNothing);
      expect(find.byType(MapSchemaView), findsOneWidget);
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

      await tester.tap(find.text(es.mapViewSchema));
      await tester.pump();
      await tester.pump();

      expect(find.byType(MapBoardView), findsNothing);
      expect(find.byType(MapSchemaView), findsOneWidget);
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

    testWidgets('en el tablero no hay nada que exportar: el botón está '
        'apagado y dice por qué', (tester) async {
      await seed();
      await pump(tester);

      final button = tester.widget<PopupMenuButton<String>>(
        find.byKey(const ValueKey('map-export')),
      );

      expect(button.enabled, isFalse);
      expect(button.tooltip, es.mapExportUnavailable);
    });

    testWidgets('en el esquema guarda un SVG con el nombre de la vista y la '
        'categoría', (tester) async {
      await seed();
      await pump(tester);
      await tester.tap(find.text(es.mapViewSchema));
      await tester.pumpAndSettle();

      await pickExport(tester, 'map-export-svg');

      expect(harness.fileSaver.savedFileName, 'mapa-esquema-etiquetas.svg');
      final text = String.fromCharCodes(harness.fileSaver.savedBytes!);
      expect(text, startsWith('<?xml'));
      expect(text, contains('Roma'));
      expect(find.text(es.mapExportSaved), findsOneWidget);
    });

    testWidgets('en el grafo guarda un PNG', (tester) async {
      await seed();
      await pump(tester);
      await tester.tap(find.text(es.mapViewGraph));
      await tester.pumpAndSettle();

      await pickExport(tester, 'map-export-png');

      expect(harness.fileSaver.savedFileName, 'mapa-grafo-etiquetas.png');
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
      await tester.tap(find.text(es.mapViewSchema));
      await tester.pumpAndSettle();
      harness.fileSaver.error = StateError('disco lleno');

      await pickExport(tester, 'map-export-svg');

      expect(find.text(es.mapExportSaved), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
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
          .assignSpaceMany(itemIds: ['s1', 's4'], spaceId: space.id);
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

    testWidgets('el filtro rige a las tres vistas: sigue puesto al cambiar de '
        'una a otra', (tester) async {
      await seed();
      await item('d1', ['roma'], kind: SourceKind.document);
      await pump(tester);
      await openFilters(tester);
      await tester.tap(find.byKey(const ValueKey('map-filter-kind-document')));
      await tester.pumpAndSettle();
      await closeSheet(tester);

      await tester.tap(find.text(es.mapViewSchema));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('map-filter-active')), findsOneWidget);

      await tester.tap(find.text(es.mapViewGraph));
      await tester.pumpAndSettle();
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

  testWidgets('la madurez de las notas sale del tablero', (tester) async {
    await seed();
    await insertItemRows(
      db,
      id: 'n1',
      title: 'Nota',
      createdAt: DateTime(2026, 8, 12),
      kind: SourceKind.manualNote,
    );
    await (db.update(
      db.knowledgeNotes,
    )..where((n) => n.itemId.equals('n1'))).write(
      const KnowledgeNotesCompanion(maturity: Value(NoteMaturity.mature)),
    );
    await pump(tester);

    expect(find.text('${es.noteMaturityMature}: 1'), findsOneWidget);
  });
}
