import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/atlas/presentation/screens/atlas_screen.dart';
import 'package:sinapsis/features/explorer/presentation/providers/explorer_providers.dart';
import 'package:sinapsis/features/explorer/presentation/screens/explorer_screen.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/features/timeline/presentation/screens/timeline_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/item_rows.dart';
import '../../../../support/library_harness.dart';

/// La pantalla del Atlas (F13), contra SQLite real y el router real: el árbol
/// con sus conteos y su cobertura, los vacíos, la búsqueda y adónde lleva cada
/// cosa.
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

  Future<void> value(
    String id,
    String label, {
    String? parent,
    int depth = 0,
    String? definitionId,
  }) => db
      .into(db.propertyValues)
      .insert(
        PropertyValuesCompanion.insert(
          id: id,
          definitionId: definitionId ?? tema,
          value: label,
          createdAt: now,
          parentId: Value(parent),
          depth: Value(depth),
        ),
      );

  Future<void> assign(String itemId, List<String> valueIds) async {
    for (final valueId in valueIds) {
      await db
          .into(db.itemPropertyValues)
          .insert(
            ItemPropertyValuesCompanion.insert(
              itemId: itemId,
              propertyValueId: valueId,
            ),
          );
    }
  }

  Future<void> source(String id, List<String> values) async {
    await insertItemRows(db, id: id, title: 'Fuente $id', createdAt: now);
    await assign(id, values);
  }

  Future<void> note(
    String id,
    NoteKind kind,
    List<String> values, {
    NoteMaturity maturity = NoteMaturity.seed,
    String? title,
  }) async {
    await insertItemRows(
      db,
      id: id,
      title: title ?? 'Nota $id',
      createdAt: now,
      kind: SourceKind.manualNote,
    );
    await (db.update(
      db.knowledgeNotes,
    )..where((n) => n.itemId.equals(id))).write(
      KnowledgeNotesCompanion(noteKind: Value(kind), maturity: Value(maturity)),
    );
    await assign(id, values);
  }

  /// Una «Fecha del hecho» de [year], puesta en [itemId].
  Future<void> factDate(String id, int year, String itemId) async {
    final fecha =
        await (db.select(db.propertyDefinitions)..where(
              (d) =>
                  d.isSystem.equals(true) &
                  d.name.equals(kFechaDelHechoCategoryName),
            ))
            .getSingle();
    await db
        .into(db.propertyValues)
        .insert(
          PropertyValuesCompanion.insert(
            id: id,
            definitionId: fecha.id,
            value: 'Año $year',
            createdAt: now,
            dateFromYear: Value(year),
            dateToYear: Value(year),
            datePrecision: const Value(DatePrecision.year),
          ),
        );
    await assign(itemId, [id]);
  }

  /// Roma ─ República ─ Gracos, Roma ─ Imperio, Grecia y Vacío solos.
  ///
  /// Roma: 3 fuentes y 2 notas debajo (una viva en construcción y un mapa);
  /// Grecia: solo fuentes; Vacío: nada.
  Future<void> seed() async {
    await value('roma', 'Roma');
    await value('republica', 'República', parent: 'roma', depth: 1);
    await value('gracos', 'Gracos', parent: 'republica', depth: 2);
    await value('imperio', 'Imperio', parent: 'roma', depth: 1);
    await value('grecia', 'Grecia');
    await value('vacio', 'Vacío');
    await source('s1', ['roma']);
    await source('s2', ['republica']);
    await source('s3', ['gracos']);
    await note('n-viva', NoteKind.living, ['republica']);
    await note('n-mapa', NoteKind.map, ['roma'], title: 'Mapa de Roma');
    await source('g1', ['grecia']);
    await source('g2', ['grecia']);
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();
    harness.goTo(RoutePaths.atlas);
    await tester.pumpAndSettle();
  }

  Finder node(String id) => find.byKey(ValueKey('atlas-node-$id'));

  Future<void> expand(WidgetTester tester, String id) async {
    await tester.tap(
      find.descendant(of: node(id), matching: find.byIcon(Icons.chevron_right)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('el árbol arranca plegado: solo las raíces, con la leyenda', (
    tester,
  ) async {
    await seed();
    await pump(tester);

    expect(find.byType(AtlasScreen), findsOneWidget);
    expect(find.text(es.atlasCoverageTitle), findsOneWidget);
    expect(node('roma'), findsOneWidget);
    expect(node('grecia'), findsOneWidget);
    expect(node('vacio'), findsOneWidget);
    expect(node('republica'), findsNothing);
    expect(node('imperio'), findsNothing);
  });

  testWidgets('cada rama dice cuántas fuentes y cuántas notas hay debajo, en '
      'cascada', (tester) async {
    await seed();
    await pump(tester);

    // Roma: las suyas más las de República y Gracos.
    expect(
      find.descendant(
        of: node('roma'),
        matching: find.text(es.atlasSourceCount(3)),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: node('roma'),
        matching: find.text(es.atlasNoteCount(2)),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: node('grecia'),
        matching: find.text(es.atlasSourceCount(2)),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: node('vacio'),
        matching: find.text(es.atlasCoverageEmpty),
      ),
      findsOneWidget,
    );
  });

  testWidgets('desplegar muestra los subtemas, con sangría', (tester) async {
    await seed();
    await pump(tester);

    await expand(tester, 'roma');
    await expand(tester, 'republica');

    expect(node('republica'), findsOneWidget);
    expect(node('imperio'), findsOneWidget);
    expect(node('gracos'), findsOneWidget);
    double left(String id, String label) => tester
        .getTopLeft(find.descendant(of: node(id), matching: find.text(label)))
        .dx;
    final romaLeft = left('roma', 'Roma');
    final gracosLeft = left('gracos', 'Gracos');
    expect(gracosLeft, greaterThan(romaLeft));
  });

  testWidgets('con el teclado: la flecha derecha despliega y la izquierda '
      'pliega', (tester) async {
    await seed();
    await pump(tester);

    // El foco en la fila, como lo dejaría Tab: el de lo que hay dentro del
    // `ListTile`, no el de la envoltura.
    Focus.of(
      tester.element(
        find.descendant(of: node('roma'), matching: find.text('Roma')),
      ),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(node('republica'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(node('republica'), findsNothing);
  });

  testWidgets('buscar encuentra el tema donde esté y conserva su camino', (
    tester,
  ) async {
    await seed();
    await pump(tester);

    await tester.enterText(
      find.byKey(const ValueKey('atlas-search')),
      'gracos',
    );
    await tester.pumpAndSettle();

    expect(node('gracos'), findsOneWidget);
    expect(node('republica'), findsOneWidget);
    expect(node('roma'), findsOneWidget);
    expect(node('grecia'), findsNothing);
    // La leyenda y los vacíos son del árbol entero: buscando no se muestran.
    expect(find.text(es.atlasCoverageTitle), findsNothing);
  });

  testWidgets('una búsqueda sin coincidencias lo dice', (tester) async {
    await seed();
    await pump(tester);

    await tester.enterText(
      find.byKey(const ValueKey('atlas-search')),
      'egipto',
    );
    await tester.pumpAndSettle();

    expect(find.text(es.atlasNoResults), findsOneWidget);
  });

  group('vacíos', () {
    testWidgets('la tarjeta lista los vacíos detectados', (tester) async {
      await seed();
      for (var i = 0; i < 4; i++) {
        await source('extra-$i', ['grecia']);
      }
      await pump(tester);

      // Grecia: 6 fuentes y ninguna nota viva. Vacío no es un vacío.
      final gaps = find.byKey(const ValueKey('atlas-gaps'));
      expect(gaps, findsOneWidget);
      expect(
        find.byKey(const ValueKey('atlas-gap-manySourcesNoLivingNote-grecia')),
        findsOneWidget,
      );
      expect(find.text(es.atlasGapManySources(6)), findsOneWidget);
      expect(
        find.byKey(const ValueKey('atlas-gap-singleItem-vacio')),
        findsNothing,
      );
    });

    testWidgets('tocar un vacío abre el Explorador ya filtrado por esa rama', (
      tester,
    ) async {
      await seed();
      for (var i = 0; i < 4; i++) {
        await source('extra-$i', ['grecia']);
      }
      await pump(tester);

      await tester.tap(
        find.byKey(const ValueKey('atlas-gap-manySourcesNoLivingNote-grecia')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ExplorerScreen), findsOneWidget);
      expect(
        harness.container.read(explorerQueryNotifierProvider).propertyValueIds,
        {'grecia'},
      );
    });

    testWidgets('sin vacíos, la tarjeta no está', (tester) async {
      await value('roma', 'Roma');
      await source('a', ['roma']);
      await source('b', ['roma']);
      await note('n', NoteKind.living, ['roma']);
      await pump(tester);

      expect(find.byKey(const ValueKey('atlas-gaps')), findsNothing);
    });
  });

  testWidgets('«Ver el material» del menú abre el Explorador filtrado por la '
      'rama', (tester) async {
    await seed();
    await pump(tester);

    await tester.tap(
      find.descendant(
        of: node('roma'),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(es.atlasOpenMaterial));
    await tester.pumpAndSettle();

    expect(find.byType(ExplorerScreen), findsOneWidget);
    expect(
      harness.container.read(explorerQueryNotifierProvider).propertyValueIds,
      {'roma'},
    );
  });

  testWidgets('una rama sin subtemas abre su material al tocarla', (
    tester,
  ) async {
    await seed();
    await pump(tester);

    await tester.tap(node('grecia'));
    await tester.pumpAndSettle();

    expect(find.byType(ExplorerScreen), findsOneWidget);
    expect(
      harness.container.read(explorerQueryNotifierProvider).propertyValueIds,
      {'grecia'},
    );
  });

  group('eje temporal', () {
    testWidgets('cada rama con fechas muestra el rango que cubre', (
      tester,
    ) async {
      await seed();
      await factDate('f1', -43, 's1');
      await factDate('f2', 476, 's3');
      await pump(tester);

      final axis = find.descendant(
        of: node('roma'),
        matching: find.byKey(const ValueKey('atlas-axis-roma')),
      );
      expect(axis, findsOneWidget);
      expect(
        find.descendant(
          of: axis,
          matching: find.text('${es.timelineYearBce(44)} – 476'),
        ),
        findsOneWidget,
      );
      // Grecia no tiene ningún elemento con fecha.
      expect(find.byKey(const ValueKey('atlas-axis-grecia')), findsNothing);
    });

    testWidgets('tocar el rango abre la línea de tiempo ya filtrada por la '
        'rama', (tester) async {
      await seed();
      await factDate('f1', -43, 's1');
      await factDate('f2', 476, 'g1');
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('atlas-axis-roma')));
      await tester.pumpAndSettle();

      expect(find.byType(TimelineScreen), findsOneWidget);
      // El filtro está rotulado con la rama y se puede quitar.
      final chip = find.byKey(const ValueKey('timeline-branch-filter'));
      expect(chip, findsOneWidget);
      expect(find.descendant(of: chip, matching: find.text('Roma')), findsOne);
      // El hecho de Grecia (476) no está: el filtro dejó solo lo de Roma.
      expect(find.text(es.timelineEventCount(1)), findsOneWidget);
    });

    testWidgets('quitar el filtro de la línea de tiempo trae todos los '
        'hechos', (tester) async {
      await seed();
      await factDate('f1', -43, 's1');
      await factDate('f2', 476, 'g1');
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('atlas-axis-roma')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(es.timelineBranchFilterTooltip));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('timeline-branch-filter')),
        findsNothing,
      );
      expect(find.text(es.timelineEventCount(2)), findsOneWidget);
    });
  });

  group('notas mapa', () {
    testWidgets('se ven como punto de entrada en su rama y se abren', (
      tester,
    ) async {
      await seed();
      await pump(tester);

      final chip = find.byKey(const ValueKey('atlas-map-roma-n-mapa'));
      expect(chip, findsOneWidget);
      expect(
        find.descendant(of: chip, matching: find.text('Mapa de Roma')),
        findsOne,
      );

      await tester.tap(chip);
      await tester.pumpAndSettle();

      expect(find.byType(ItemDetailScreen), findsOneWidget);
    });

    testWidgets('con más de dos, el resto va detrás de «+N»', (tester) async {
      await seed();
      await note('m2', NoteKind.map, ['roma'], title: 'Mapa dos');
      await note('m3', NoteKind.map, ['roma'], title: 'Mapa tres');
      await pump(tester);

      final more = find.byKey(const ValueKey('atlas-map-more-roma'));
      expect(more, findsOneWidget);
      expect(find.descendant(of: more, matching: find.text('+1')), findsOne);

      await tester.tap(more);
      await tester.pumpAndSettle();

      expect(find.text(es.atlasMapNotesTitle), findsOneWidget);
      expect(find.byKey(const ValueKey('atlas-map-sheet-m3')), findsOneWidget);
    });
  });

  testWidgets('asignar una propiedad se refleja sin recargar', (tester) async {
    await seed();
    await pump(tester);
    expect(
      find.descendant(
        of: node('grecia'),
        matching: find.text(es.atlasSourceCount(2)),
      ),
      findsOneWidget,
    );

    await source('g3', ['grecia']);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: node('grecia'),
        matching: find.text(es.atlasSourceCount(3)),
      ),
      findsOneWidget,
    );
  });

  testWidgets('una categoría sin valores muestra el estado vacío', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text(es.atlasEmptyTitle), findsOneWidget);
  });

  testWidgets('el selector cambia de categoría', (tester) async {
    await seed();
    await db
        .into(db.propertyDefinitions)
        .insert(
          PropertyDefinitionsCompanion.insert(
            id: 'def-personaje',
            name: 'Personaje',
            createdAt: now,
            type: const Value(PropertyValueType.text),
          ),
        );
    await value('cesar', 'César', definitionId: 'def-personaje');
    await source('s-cesar', ['cesar']);
    await pump(tester);
    expect(node('roma'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('atlas-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Personaje').last);
    await tester.pumpAndSettle();

    expect(node('cesar'), findsOneWidget);
    expect(node('roma'), findsNothing);
  });

  group('exportar', () {
    testWidgets('el botón guarda el Atlas como Markdown y lo avisa', (
      tester,
    ) async {
      await seed();
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('atlas-export')));
      await tester.pumpAndSettle();

      expect(harness.fileSaver.savedFileName, 'atlas-tema.md');
      final markdown = utf8.decode(harness.fileSaver.savedBytes!);
      // La jerarquía entera, plegada o no en la pantalla.
      expect(markdown, startsWith('# Atlas — Tema'));
      expect(markdown, contains('- **Roma** — En construcción · 3 fuentes'));
      expect(markdown, contains('  - **República** —'));
      expect(markdown, contains('    - **Gracos** —'));
      expect(markdown, contains('[[Mapa de Roma]]'));
      expect(find.text(es.atlasExportSaved), findsOneWidget);
    });

    testWidgets('si el guardado falla, lo dice', (tester) async {
      await seed();
      await pump(tester);
      harness.fileSaver.error = Exception('sin espacio');

      await tester.tap(find.byKey(const ValueKey('atlas-export')));
      await tester.pumpAndSettle();

      expect(find.text(es.atlasExportSaved), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('exporta la categoría que se está viendo', (tester) async {
      await seed();
      await db
          .into(db.propertyDefinitions)
          .insert(
            PropertyDefinitionsCompanion.insert(
              id: 'def-personaje',
              name: 'Personaje histórico',
              createdAt: now,
              type: const Value(PropertyValueType.text),
            ),
          );
      await value('cesar', 'César', definitionId: 'def-personaje');
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('atlas-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Personaje histórico').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('atlas-export')));
      await tester.pumpAndSettle();

      expect(harness.fileSaver.savedFileName, 'atlas-personaje-historico.md');
      expect(
        utf8.decode(harness.fileSaver.savedBytes!),
        contains('# Atlas — Personaje histórico'),
      );
    });
  });
}
