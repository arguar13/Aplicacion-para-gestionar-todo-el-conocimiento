import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/explorer/presentation/screens/explorer_screen.dart';
import 'package:sinapsis/features/map/presentation/screens/map_screen.dart';
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
