import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_filter.dart';
import 'package:sinapsis/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:sinapsis/features/timeline/presentation/screens/timeline_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';
import '../../../../support/processed_rows.dart';
import '../../timeline_fixtures.dart';

/// «Ver en la línea de tiempo», en el detalle de un elemento con fechas (F40).
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late AppDatabase db;
  late String fechaId;
  final now = DateTime(2026, 10, 26, 10);

  setUp(() async {
    harness = await LibraryHarness.create();
    db = harness.database;
    fechaId =
        (await (db.select(db.propertyDefinitions)..where(
                  (d) =>
                      d.isSystem.equals(true) &
                      d.name.equals(kFechaDelHechoCategoryName),
                ))
                .getSingle())
            .id;
  });

  Future<void> saveSource(String id, String title) => harness.container
      .read(libraryRepositoryProvider)
      .save(
        KnowledgeItem(
          id: id,
          title: title,
          source: Source(
            id: 'src-$id',
            kind: SourceKind.webPage,
            capturedAt: now,
            url: 'https://e.org/$id',
          ),
          processingState: ProcessingState.ready,
          createdAt: now,
          updatedAt: now,
        ),
      );

  /// Una fuente [id] y, con [processed], su documento procesado `p-$id`: la
  /// línea de tiempo lee lo procesado (F41, paso 6).
  Future<void> save(String id, String title, {bool processed = true}) async {
    await saveSource(id, title);
    if (!processed) return;
    await insertProcessedDocument(
      db,
      id: 'p-$id',
      title: title,
      createdAt: now,
    );
    await (db.update(db.processedDocuments)
          ..where((d) => d.itemId.equals('p-$id')))
        .write(ProcessedDocumentsCompanion(sourceItemId: Value(id)));
  }

  Future<void> dateOn(String itemId, int year) async {
    final organize = harness.container.read(organizeRepositoryProvider);
    final value = (await organize.getOrCreateHistoricalPropertyValue(
      definitionId: fechaId,
      date: dateOf(year),
    )).getRight().toNullable()!;
    await organize.assignProperty(
      itemId: itemId,
      definitionId: fechaId,
      value: value.value,
    );
  }

  /// Una fuente cuyo documento procesado tiene una «Fecha del hecho» de
  /// verdad, puesta por el camino de la app.
  Future<void> dated(String id, String title, int year) async {
    await save(id, title);
    await dateOn('p-$id', year);
  }

  Future<void> openDetail(WidgetTester tester, String id) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();
    harness.goTo(RoutePaths.itemDetail(id));
    await tester.pumpAndSettle();
  }

  final link = find.byKey(const ValueKey('item-timeline-link'));

  testWidgets('una fuente cuyo documento procesado tiene fecha ofrece verla en '
      'la línea de tiempo', (tester) async {
    await dated('roma', 'Caída de Roma', 476);

    await openDetail(tester, 'roma');

    expect(link, findsOneWidget);
    expect(
      find.descendant(of: link, matching: find.text(es.detailOpenTimeline)),
      findsOneWidget,
    );
  });

  testWidgets('abre la línea de tiempo filtrada por ese documento, con su '
      'chip', (tester) async {
    await dated('roma', 'Caída de Roma', 476);
    await dated('cesar', 'César', 44);
    await openDetail(tester, 'roma');

    await tester.tap(link);
    await tester.pumpAndSettle();

    expect(find.byType(TimelineScreen), findsOneWidget);
    // Cambia de destino de la barra, en «Organizar»: no se apila encima.
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(
      (rail.destinations[rail.selectedIndex!].label as Text).data,
      es.navTimeline,
    );
    final scope = harness.container.read(timelineFilterProvider).scope;
    expect(scope?.kind, TimelineScopeKind.document);
    expect(scope?.id, 'p-roma');
    expect(scope?.label, 'Caída de Roma');
    // Solo el hecho de ese documento.
    expect(find.text(es.timelineEventCount(1)), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('timeline-scope-document')),
        matching: find.text('Caída de Roma'),
      ),
      findsOneWidget,
    );

    // El detalle ya no vive en el shell: al irse a la línea de tiempo se
    // suelta, y drift cierra sus consultas con un temporizador que hay que
    // dejar correr.
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('un elemento sin ninguna fecha no ofrece nada, aunque otros '
      'sí tengan', (tester) async {
    await dated('otro', 'Otro', 1500);
    await save('sin', 'Sin fecha');

    await openDetail(tester, 'sin');

    expect(link, findsNothing);
  });

  testWidgets('una «Fecha del hecho» que es solo un texto, sin año ni '
      'precisión, tampoco: la línea saldría vacía', (tester) async {
    await save('texto', 'Con un texto');
    await harness.container
        .read(organizeRepositoryProvider)
        .assignProperty(
          itemId: 'p-texto',
          definitionId: fechaId,
          value: 'cuando sea',
        );

    await openDetail(tester, 'texto');

    expect(link, findsNothing);
  });

  testWidgets('aparece solo al ponerle una fecha, sin salir del detalle', (
    tester,
  ) async {
    await save('nuevo', 'Nuevo');
    await openDetail(tester, 'nuevo');
    expect(link, findsNothing);

    final organize = harness.container.read(organizeRepositoryProvider);
    final value = (await organize.getOrCreateHistoricalPropertyValue(
      definitionId: fechaId,
      date: dateOf(1500),
    )).getRight().toNullable()!;
    await organize.assignProperty(
      itemId: 'p-nuevo',
      definitionId: fechaId,
      value: value.value,
    );
    await tester.pumpAndSettle();

    expect(link, findsOneWidget);
  });

  testWidgets('la fecha que la fuente ya tenía no ofrece la línea: empieza de '
      'cero, con lo procesado (F41, paso 6)', (tester) async {
    await save('vieja', 'Vieja', processed: false);
    await dateOn('vieja', 476);

    await openDetail(tester, 'vieja');

    expect(link, findsNothing);
  });
}
