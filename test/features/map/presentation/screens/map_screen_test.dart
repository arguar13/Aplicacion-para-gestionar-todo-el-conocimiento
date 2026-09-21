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
import 'package:sinapsis/features/explorer/presentation/screens/explorer_screen.dart';
import 'package:sinapsis/features/map/presentation/screens/map_screen.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_board_view.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_schema_view.dart';
import 'package:sinapsis/features/relations/presentation/screens/tension_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

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
    harness.goTo(RoutePaths.map);
    await tester.pumpAndSettle();
  }

  testWidgets('sin temas, dice que todavía no hay', (tester) async {
    await pump(tester);

    expect(find.byType(MapScreen), findsOneWidget);
    expect(find.text(es.mapEmptyTitle), findsOneWidget);
  });

  testWidgets('muestra el tablero de lo que hay en la bóveda', (tester) async {
    await seed();
    await pump(tester);

    expect(find.text(es.mapTitle), findsOneWidget);
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
