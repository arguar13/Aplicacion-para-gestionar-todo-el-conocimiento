import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/vocabulary/presentation/screens/vocabulary_category_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// El explorador de UNA categoría, contra SQLite real.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late AppDatabase db;
  late String tema;

  final now = DateTime(2026, 9, 19, 10);

  setUp(() async {
    harness = await LibraryHarness.create();
    db = harness.database;
    tema = await temaDefinitionId(db);
  });

  Future<void> seedItem(String id) async {
    await db
        .into(db.sources)
        .insert(
          SourcesCompanion.insert(
            id: 'src-$id',
            kind: SourceKind.webPage,
            capturedAt: now,
          ),
        );
    await db
        .into(db.items)
        .insert(
          ItemsCompanion.insert(
            id: id,
            title: 'Elemento $id',
            sourceId: 'src-$id',
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<void> addValue(
    String id,
    String label, {
    List<String> items = const [],
  }) async {
    await db
        .into(db.propertyValues)
        .insert(
          PropertyValuesCompanion.insert(
            id: id,
            definitionId: tema,
            value: label,
            createdAt: now,
          ),
        );
    for (final itemId in items) {
      await db
          .into(db.itemPropertyValues)
          .insert(
            ItemPropertyValuesCompanion.insert(
              itemId: itemId,
              propertyValueId: id,
            ),
          );
    }
  }

  Future<void> seedValues() async {
    for (final id in ['i1', 'i2', 'i3']) {
      await seedItem(id);
    }
    await addValue('roma', 'Roma', items: ['i1', 'i2']);
    await addValue('roma-acento', 'Róma', items: ['i3']);
    await addValue('egipto', 'Egipto', items: ['i1']);
    await addValue('cancion', 'Canción');
  }

  Future<void> pumpCategory(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      harness.wrap(VocabularyCategoryScreen(definitionId: tema)),
    );
    await tester.pumpAndSettle();
  }

  Future<List<String>> temaLabels() async =>
      ((await (db.select(
            db.propertyValues,
          )..where((v) => v.definitionId.equals(tema))).get()).map(
            (v) => v.value,
          ))
          .toList()
        ..sort();

  Future<List<String>> aliasesOf(String valueId) async =>
      (await (db.select(
            db.propertyAliases,
          )..where((a) => a.propertyValueId.equals(valueId))).get())
          .map((a) => a.alias)
          .toList()
        ..sort();

  testWidgets('lista los valores de la categoría con cuánto se usa cada uno', (
    tester,
  ) async {
    await seedValues();

    await pumpCategory(tester);

    expect(find.text('Tema'), findsOneWidget); // el título
    expect(find.text('Roma'), findsOneWidget);
    expect(find.text('Róma'), findsOneWidget);
    expect(find.text('Egipto'), findsOneWidget);
    expect(find.text(es.vocabularyUsage(2)), findsOneWidget); // Roma
    expect(find.text(es.vocabularyUsage(0)), findsOneWidget); // Canción
  });

  testWidgets('una categoría sin valores lo explica', (tester) async {
    await pumpCategory(tester);

    expect(find.text(es.vocabularyCategoryEmpty), findsOneWidget);
  });

  group('buscar', () {
    testWidgets('filtra sin distinguir acentos ni mayúsculas', (tester) async {
      await seedValues();
      await pumpCategory(tester);

      await tester.enterText(find.byType(TextField), 'CANCION');
      await tester.pumpAndSettle();

      expect(find.text('Canción'), findsOneWidget);
      expect(find.text('Roma'), findsNothing);
    });

    testWidgets('encuentra el valor con o sin acento escrito', (tester) async {
      await seedValues();
      await pumpCategory(tester);

      await tester.enterText(find.byType(TextField), 'roma');
      await tester.pumpAndSettle();

      expect(find.text('Roma'), findsOneWidget);
      expect(find.text('Róma'), findsOneWidget);
      expect(find.text('Egipto'), findsNothing);
    });

    testWidgets('sin coincidencias lo dice', (tester) async {
      await seedValues();
      await pumpCategory(tester);

      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();

      expect(find.text(es.vocabularySearchNoResults), findsOneWidget);
    });
  });

  group('un valor', () {
    Future<void> openValue(WidgetTester tester, String label) async {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    testWidgets('tocarlo abre su detalle, con su nombre, su uso y sus alias', (
      tester,
    ) async {
      await seedValues();
      await db
          .into(db.propertyAliases)
          .insert(
            PropertyAliasesCompanion.insert(
              id: 'a1',
              propertyValueId: 'roma',
              definitionId: tema,
              alias: 'Urbe',
              createdAt: now,
            ),
          );
      await pumpCategory(tester);

      await openValue(tester, 'Roma');

      expect(find.text(es.vocabularyAliasesTitle), findsOneWidget);
      expect(find.text('Urbe'), findsOneWidget);
    });

    testWidgets('sin alias lo explica', (tester) async {
      await seedValues();
      await pumpCategory(tester);

      await openValue(tester, 'Egipto');

      expect(find.text(es.vocabularyAliasesEmpty), findsOneWidget);
    });

    testWidgets('agregar un alias lo guarda y se puede deshacer', (
      tester,
    ) async {
      await seedValues();
      await pumpCategory(tester);
      await openValue(tester, 'Roma');

      await tester.enterText(
        find.widgetWithText(TextField, es.vocabularyAddAliasLabel),
        'Urbe eterna',
      );
      await tester.tap(find.text(es.vocabularyAddAliasAction));
      await tester.pumpAndSettle();

      expect(await aliasesOf('roma'), ['Urbe eterna']);
      expect(find.text('Urbe eterna'), findsOneWidget);
      expect(
        find.text(es.vocabularyOperationAliasAdded('Urbe eterna')),
        findsOneWidget,
      );

      await tester.tap(find.text(es.vocabularyUndoAction));
      await tester.pumpAndSettle();

      expect(await aliasesOf('roma'), isEmpty);
    });

    testWidgets('un alias que ya existe no se agrega y queda el texto para '
        'corregirlo', (tester) async {
      await seedValues();
      await pumpCategory(tester);
      await openValue(tester, 'Roma');

      final field = find.widgetWithText(TextField, es.vocabularyAddAliasLabel);
      await tester.enterText(field, 'egipto'); // ya es el nombre de un valor
      await tester.tap(find.text(es.vocabularyAddAliasAction));
      await tester.pumpAndSettle();

      expect(await aliasesOf('roma'), isEmpty);
      expect(find.byType(SnackBar), findsOneWidget);
      // Sigue escrito, para poder corregirlo.
      expect(tester.widget<TextField>(field).controller!.text, 'egipto');
    });

    testWidgets('quitar un alias lo borra y se puede volver a poner', (
      tester,
    ) async {
      await seedValues();
      await db
          .into(db.propertyAliases)
          .insert(
            PropertyAliasesCompanion.insert(
              id: 'a1',
              propertyValueId: 'roma',
              definitionId: tema,
              alias: 'Urbe',
              createdAt: now,
            ),
          );
      await pumpCategory(tester);
      await openValue(tester, 'Roma');

      await tester.tap(find.byTooltip(es.vocabularyRemoveAliasTooltip('Urbe')));
      await tester.pumpAndSettle();

      expect(await aliasesOf('roma'), isEmpty);

      await tester.tap(find.text(es.vocabularyUndoAction));
      await tester.pumpAndSettle();

      expect(await aliasesOf('roma'), ['Urbe']);
    });

    testWidgets('renombrarlo desde la hoja cambia el nombre', (tester) async {
      await seedValues();
      await pumpCategory(tester);
      await openValue(tester, 'Egipto');

      await tester.tap(find.byTooltip(es.commonRename));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Antiguo Egipto');
      await tester.tap(find.text(es.commonRename).last);
      await tester.pumpAndSettle();

      expect(await temaLabels(), contains('Antiguo Egipto'));
      expect(await temaLabels(), isNot(contains('Egipto')));
    });
  });

  group('fusionar los marcados', () {
    testWidgets('el botón aparece con dos marcados, no con uno', (
      tester,
    ) async {
      await seedValues();
      await pumpCategory(tester);

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(find.text(es.vocabularyMergeSelected(1)), findsNothing);
      expect(find.byType(FilledButton), findsNothing);

      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pumpAndSettle();

      expect(find.text(es.vocabularyMergeSelected(2)), findsOneWidget);
    });

    testWidgets('elige cuál se conserva (por defecto el más usado), pide '
        'confirmación con el conteo, fusiona y se puede deshacer', (
      tester,
    ) async {
      await seedValues();
      await pumpCategory(tester);
      // Orden alfabético sin acentos: Canción, Egipto, Roma, Róma. Se marcan
      // Roma y Róma.
      await tester.tap(find.byType(Checkbox).at(2));
      await tester.tap(find.byType(Checkbox).at(3));
      await tester.pumpAndSettle();

      await tester.tap(find.text(es.vocabularyMergeSelected(2)));
      await tester.pumpAndSettle();
      // El diálogo de "cuál se conserva": Roma (2 elementos) está primero.
      expect(find.text(es.vocabularyChooseKeepTitle), findsOneWidget);
      await tester.tap(find.text(es.vocabularyMergeConfirmAction));
      await tester.pumpAndSettle();

      // La confirmación, con cuántos elementos toca: Róma la tiene 1.
      expect(
        find.text(es.vocabularyMergeConfirmBody(1, 'Roma', 1)),
        findsOneWidget,
      );
      await tester.tap(find.text(es.vocabularyMergeConfirmAction));
      await tester.pumpAndSettle();

      expect(await temaLabels(), isNot(contains('Róma')));
      expect(await aliasesOf('roma'), ['Róma']);

      await tester.tap(find.text(es.vocabularyUndoAction));
      await tester.pumpAndSettle();

      expect(await temaLabels(), contains('Róma'));
      expect(await aliasesOf('roma'), isEmpty);
    });

    testWidgets('se puede elegir otro valor para conservar', (tester) async {
      await seedValues();
      await pumpCategory(tester);
      await tester.tap(find.byType(Checkbox).at(2));
      await tester.tap(find.byType(Checkbox).at(3));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.vocabularyMergeSelected(2)));
      await tester.pumpAndSettle();

      // En el diálogo, elegir "Róma" en vez de "Roma".
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Róma'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.vocabularyMergeConfirmAction));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.vocabularyMergeConfirmAction));
      await tester.pumpAndSettle();

      // Se conservó Róma; Roma pasó a ser su alias.
      expect(await temaLabels(), isNot(contains('Roma')));
      expect(await aliasesOf('roma-acento'), ['Roma']);
    });

    testWidgets('cancelar en cualquiera de los dos diálogos no cambia nada', (
      tester,
    ) async {
      await seedValues();
      await pumpCategory(tester);
      await tester.tap(find.byType(Checkbox).at(2));
      await tester.tap(find.byType(Checkbox).at(3));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.vocabularyMergeSelected(2)));
      await tester.pumpAndSettle();

      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      expect(await temaLabels(), containsAll(['Roma', 'Róma']));
    });
  });

  testWidgets('Tema con 2.000 valores: la lista se construye de a poco y la '
      'búsqueda la acota', (tester) async {
    await db.batch((batch) {
      batch.insertAll(db.propertyValues, [
        for (var i = 0; i < 2000; i++)
          PropertyValuesCompanion.insert(
            id: 'v$i',
            definitionId: tema,
            value: 'Valor ${i.toRadixString(36)}k$i',
            createdAt: now,
          ),
      ]);
    });

    await pumpCategory(tester);

    expect(find.byType(ListTile).evaluate().length, lessThan(60));

    await tester.enterText(find.byType(TextField), 'k1999');
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsOneWidget);
  });

  test('la ruta del explorador arma la dirección de la categoría', () {
    expect(RoutePaths.vocabularyCategory('abc'), '/vocabulary/category/abc');
  });
}
