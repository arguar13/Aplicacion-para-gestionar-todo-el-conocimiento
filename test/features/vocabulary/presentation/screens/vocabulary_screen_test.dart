import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/features/vocabulary/domain/services/merge_candidates.dart';
import 'package:sinapsis/features/vocabulary/presentation/providers/vocabulary_providers.dart';
import 'package:sinapsis/features/vocabulary/presentation/screens/vocabulary_category_screen.dart';
import 'package:sinapsis/features/vocabulary/presentation/screens/vocabulary_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/item_rows.dart';
import '../../../../support/library_harness.dart';

/// La pantalla de mantenimiento del vocabulario, contra SQLite real.
///
/// Los candidatos se calculan con la versión síncrona: el isolate real de
/// `compute` no corre bajo el reloj simulado de `testWidgets`. Que el cálculo
/// en sí sea correcto y rápido lo prueban los tests de `merge_candidates`.
///
/// Se sobrescribe el provider de los GRUPOS y no algo de lo que depende: un
/// `ProviderScope` anidado solo cambia los providers que sobrescribe él mismo,
/// y uno sin sobrescribir sigue leyendo sus dependencias del contenedor raíz.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late AppDatabase db;

  final now = DateTime(2026, 9, 19, 10);

  setUp(() async {
    harness = await LibraryHarness.create();
    db = harness.database;
  });

  Future<void> seedItem(String id) =>
      insertItemRows(db, id: id, title: 'Elemento $id', createdAt: now);

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
            definitionId: await temaDefinitionId(db),
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

  /// "Roma" (2 elementos), "Róma" (1) y "Roma antigua" (1): un grupo de
  /// candidatos; "Egipto" (3): sin candidatos; "Sobrante": sin uso; y una
  /// categoría vacía.
  Future<void> seedVocabulary() async {
    for (final id in ['i1', 'i2', 'i3', 'i4']) {
      await seedItem(id);
    }
    await addValue('roma', 'Roma', items: ['i1', 'i2']);
    await addValue('roma-acento', 'Róma', items: ['i3']);
    await addValue('roma-antigua', 'Roma antigua', items: ['i4']);
    await addValue('egipto', 'Egipto', items: ['i1', 'i2', 'i3']);
    await addValue('sobrante', 'Sobrante');
    await db
        .into(db.propertyDefinitions)
        .insert(
          PropertyDefinitionsCompanion.insert(
            id: 'def-vacia',
            name: 'Vacía',
            createdAt: now,
            type: const Value(PropertyValueType.text),
          ),
        );
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      harness.wrap(
        ProviderScope(
          overrides: [
            mergeCandidateGroupsProvider.overrideWith((ref) async {
              final stats = await ref.watch(
                vocabularyValueStatsProvider.future,
              );
              return groupMergeCandidates(findMergeCandidates(stats));
            }),
          ],
          child: const VocabularyScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<List<String>> temaLabels() async {
    final tema = await temaDefinitionId(db);
    return ((await (db.select(
          db.propertyValues,
        )..where((v) => v.definitionId.equals(tema))).get()).map(
          (v) => v.value,
        ))
        .toList()
      ..sort();
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    // Las pestañas se desplazan: con cinco, la última puede quedar fuera de
    // la pantalla, y tocarla ahí no llega a nada.
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('las pestañas muestran cuántas hay de cada cosa', (tester) async {
    await seedVocabulary();

    await pumpScreen(tester);

    expect(find.text(es.vocabularyTabCandidates(1)), findsOneWidget);
    // "Róma" y "Roma antigua": un elemento cada uno.
    expect(find.text(es.vocabularyTabSingleUse(2)), findsOneWidget);
    expect(find.text(es.vocabularyTabUnused(1)), findsOneWidget);
    expect(find.text(es.vocabularyTabEmptyCategories(1)), findsOneWidget);
  });

  testWidgets('sin nada que mantener, cada pestaña lo explica', (tester) async {
    await pumpScreen(tester);

    expect(find.text(es.vocabularyCandidatesEmpty), findsOneWidget);
    await openTab(tester, es.vocabularyTabSingleUse(0));
    expect(find.text(es.vocabularySingleUseEmpty), findsOneWidget);
    await openTab(tester, es.vocabularyTabUnused(0));
    expect(find.text(es.vocabularyUnusedEmpty), findsOneWidget);
    await openTab(tester, es.vocabularyTabEmptyCategories(0));
    expect(find.text(es.vocabularyEmptyCategoriesEmpty), findsOneWidget);
  });

  group('parecidos', () {
    testWidgets('el grupo muestra sus valores y sugiere conservar el más '
        'usado, marcando solo el casi seguro igual', (tester) async {
      await seedVocabulary();

      await pumpScreen(tester);

      expect(find.text('Roma'), findsOneWidget);
      expect(find.text('Róma'), findsOneWidget);
      expect(find.text('Roma antigua'), findsOneWidget);
      // Roma se conserva; Róma (mismo texto) queda marcada; "Roma antigua"
      // solo comparte palabras: sin marcar.
      final checkboxes = tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .toList();
      expect(checkboxes.map((c) => c.value), [false, true, false]);
      expect(checkboxes[0].onChanged, isNull); // el que se conserva
      expect(find.text(es.vocabularyMergeAction(1, 'Roma')), findsOneWidget);
    });

    testWidgets('marcar otro valor lo suma a la fusión', (tester) async {
      await seedVocabulary();
      await pumpScreen(tester);

      await tester.tap(find.byType(Checkbox).at(2));
      await tester.pumpAndSettle();

      expect(find.text(es.vocabularyMergeAction(2, 'Roma')), findsOneWidget);
    });

    testWidgets('elegir otro valor para conservar cambia el botón y suelta '
        'su casilla', (tester) async {
      await seedVocabulary();
      await pumpScreen(tester);

      await tester.tap(find.byTooltip(es.vocabularyKeepTooltip).at(1));
      await tester.pumpAndSettle();

      expect(find.text(es.vocabularyMergeAction(1, 'Róma')), findsOneWidget);
      final checkboxes = tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .toList();
      // Róma ya no se fusiona consigo misma; Roma pasó a poder marcarse
      // —y quedó marcada por ser el casi seguro igual—.
      expect(checkboxes[1].onChanged, isNull);
      expect(checkboxes[0].onChanged, isNotNull);
    });

    testWidgets('fusionar pide confirmación con cuántos elementos afecta, '
        'fusiona, y se puede deshacer desde el aviso', (tester) async {
      await seedVocabulary();
      await pumpScreen(tester);

      await tester.tap(find.text(es.vocabularyMergeAction(1, 'Roma')));
      await tester.pumpAndSettle();

      // La vista previa: Róma la tiene 1 elemento.
      expect(
        find.text(es.vocabularyMergeConfirmBody(1, 'Roma', 1)),
        findsOneWidget,
      );
      // Todavía no se cambió nada.
      expect(await temaLabels(), contains('Róma'));

      await tester.tap(find.text(es.vocabularyMergeConfirmAction));
      await tester.pumpAndSettle();

      expect(await temaLabels(), isNot(contains('Róma')));
      expect(
        find.text(es.vocabularyOperationMerged(1, 'Roma')),
        findsOneWidget,
      );

      await tester.tap(find.text(es.vocabularyUndoAction));
      await tester.pumpAndSettle();

      expect(await temaLabels(), contains('Róma'));
      expect(find.text(es.vocabularyUndone), findsOneWidget);
    });

    testWidgets('cancelar la confirmación no cambia nada', (tester) async {
      await seedVocabulary();
      await pumpScreen(tester);
      await tester.tap(find.text(es.vocabularyMergeAction(1, 'Roma')));
      await tester.pumpAndSettle();

      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      expect(await temaLabels(), contains('Róma'));
    });

    group('sugerencia de jerarquía', () {
      final putUnder = es.vocabularyPutUnderAction('Roma antigua', 'Roma');

      Future<(String?, int)> placementOf(String id) async {
        final row = await (db.select(
          db.propertyValues,
        )..where((v) => v.id.equals(id))).getSingle();
        return (row.parentId, row.depth);
      }

      testWidgets('«Roma antigua» se propone bajo «Roma», una sola vez aunque '
          '«Róma» también la contenga', (tester) async {
        await seedVocabulary();

        await pumpScreen(tester);

        expect(find.text(es.vocabularySubtopicSuggestionsTitle), findsOne);
        expect(find.text(putUnder), findsOneWidget);
        expect(
          find.text(es.vocabularyPutUnderAction('Roma antigua', 'Róma')),
          findsNothing,
        );
      });

      testWidgets('sin valores que se contengan, la tarjeta no propone '
          'nada', (tester) async {
        await seedItem('i1');
        await addValue('roma', 'Roma', items: ['i1']);
        await addValue('roma-acento', 'Róma', items: ['i1']);

        await pumpScreen(tester);

        expect(find.text(es.vocabularySubtopicSuggestionsTitle), findsNothing);
      });

      testWidgets('aceptarla pide confirmación, dice cuánto mueve y mueve; '
          'la propuesta ya no está', (tester) async {
        await seedVocabulary();
        await pumpScreen(tester);

        await tester.tap(find.text(putUnder));
        await tester.pumpAndSettle();

        // La confirmación, y todavía nada cambió.
        expect(find.text(es.vocabularyMoveConfirmTitle), findsOneWidget);
        expect(
          find.text(es.vocabularyMoveConfirmBody(1, 'Roma antigua', 'Roma')),
          findsOneWidget,
        );
        expect(await placementOf('roma-antigua'), (null, 0));

        await tester.tap(find.text(es.vocabularyMoveConfirmAction));
        await tester.pumpAndSettle();

        expect(await placementOf('roma-antigua'), ('roma', 1));
        expect(
          find.text(es.vocabularyOperationMoved(1, 'Roma antigua')),
          findsOneWidget,
        );
        expect(find.text(putUnder), findsNothing);
        // La fusión sigue disponible: son cosas distintas.
        expect(find.text(es.vocabularyMergeAction(1, 'Roma')), findsOneWidget);
      });

      testWidgets('cancelar la confirmación no cambia nada', (tester) async {
        await seedVocabulary();
        await pumpScreen(tester);

        await tester.tap(find.text(putUnder));
        await tester.pumpAndSettle();
        await tester.tap(find.text(es.commonCancel));
        await tester.pumpAndSettle();

        expect(await placementOf('roma-antigua'), (null, 0));
        expect(find.text(putUnder), findsOneWidget);
      });

      testWidgets('«Deshacer» del aviso la devuelve a la raíz y la propuesta '
          'vuelve', (tester) async {
        await seedVocabulary();
        await pumpScreen(tester);
        await tester.tap(find.text(putUnder));
        await tester.pumpAndSettle();
        await tester.tap(find.text(es.vocabularyMoveConfirmAction));
        await tester.pumpAndSettle();

        await tester.tap(find.text(es.vocabularyUndoAction));
        await tester.pumpAndSettle();

        expect(await placementOf('roma-antigua'), (null, 0));
        expect(find.text(putUnder), findsOneWidget);
      });
    });
  });

  group('un solo uso', () {
    testWidgets('renombrar cambia el nombre y avisa', (tester) async {
      await seedVocabulary();
      await pumpScreen(tester);
      await openTab(tester, es.vocabularyTabSingleUse(2));

      await tester.tap(find.byTooltip(es.commonRename).last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Roma clásica');
      await tester.tap(find.text(es.commonRename).last);
      await tester.pumpAndSettle();

      expect(await temaLabels(), contains('Roma clásica'));
      expect(
        find.text(es.vocabularyOperationRenamed('Roma clásica')),
        findsOneWidget,
      );
    });

    testWidgets('un nombre que choca no cambia nada y avisa del fallo', (
      tester,
    ) async {
      await seedVocabulary();
      await pumpScreen(tester);
      await openTab(tester, es.vocabularyTabSingleUse(2));

      await tester.tap(find.byTooltip(es.commonRename).last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ROMA');
      await tester.tap(find.text(es.commonRename).last);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(await temaLabels(), containsAll(['Roma', 'Roma antigua']));
    });
  });

  group('sin uso', () {
    testWidgets('marcar y borrar, con confirmación y deshacer desde la barra '
        'superior', (tester) async {
      await seedVocabulary();
      await pumpScreen(tester);
      await openTab(tester, es.vocabularyTabUnused(1));

      await tester.tap(find.text(es.vocabularySelectAll));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.vocabularyDeleteAction(1)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.commonDelete));
      await tester.pumpAndSettle();

      expect(await temaLabels(), isNot(contains('Sobrante')));
      expect(find.text(es.vocabularyOperationDeleted(1)), findsOneWidget);

      // Deshacer desde la barra superior, no desde el aviso.
      await tester.tap(find.byTooltip(es.vocabularyUndoTooltip));
      await tester.pumpAndSettle();

      expect(await temaLabels(), contains('Sobrante'));
    });

    testWidgets('sin marcar nada no hay botón de borrar', (tester) async {
      await seedVocabulary();
      await pumpScreen(tester);
      await openTab(tester, es.vocabularyTabUnused(1));

      expect(find.text(es.vocabularyDeleteAction(1)), findsNothing);
    });
  });

  group('categorías vacías', () {
    testWidgets('borrar una pide confirmación y se puede deshacer', (
      tester,
    ) async {
      await seedVocabulary();
      await pumpScreen(tester);
      await openTab(tester, es.vocabularyTabEmptyCategories(1));

      await tester.tap(
        find.byTooltip(es.vocabularyDeleteCategoryTooltip('Vacía')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.commonDelete));
      await tester.pumpAndSettle();

      Future<List<String>> names() async =>
          (await db.select(db.propertyDefinitions).get())
              .map((d) => d.name)
              .toList();
      expect(await names(), isNot(contains('Vacía')));

      await tester.tap(find.text(es.vocabularyUndoAction));
      await tester.pumpAndSettle();

      expect(await names(), contains('Vacía'));
    });
  });

  group('categorías', () {
    testWidgets('la pestaña lista todas, con cuántos valores tiene cada una', (
      tester,
    ) async {
      await seedVocabulary();
      await pumpScreen(tester);

      // Tema, Fecha del hecho, Autor y la vacía: 4.
      await openTab(tester, es.vocabularyTabCategories(4));

      expect(find.text('Tema'), findsOneWidget);
      expect(find.text(es.vocabularyCategoryValueCount(5)), findsOneWidget);
      expect(find.text('Vacía'), findsOneWidget);
      expect(find.text(es.vocabularyCategoryValueCount(0)), findsWidgets);
    });

    testWidgets('tocar una categoría abre su explorador, con el router real', (
      tester,
    ) async {
      await seedVocabulary();
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();
      harness.goTo(RoutePaths.vocabulary);
      // Sin `pumpAndSettle`: la pantalla real calcula los candidatos en un
      // isolate (`compute`), que no corre bajo el reloj simulado, y su
      // indicador de carga anima para siempre.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final tab = find.textContaining('Categorías (');
      await tester.ensureVisible(tab);
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(tab);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Vacía'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(VocabularyCategoryScreen), findsOneWidget);
    });
  });

  testWidgets('deshacer en la barra superior está apagado hasta que se hace '
      'algo', (tester) async {
    await seedVocabulary();
    await pumpScreen(tester);

    final button = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.undo),
    );

    expect(button.onPressed, isNull);
  });

  testWidgets('Tema con 2.000 valores: la pantalla abre y las listas se '
      'construyen de a poco', (tester) async {
    final tema = await temaDefinitionId(db);
    await db.batch((batch) {
      batch.insertAll(db.propertyValues, [
        for (var i = 0; i < 2000; i++)
          PropertyValuesCompanion.insert(
            id: 'v$i',
            definitionId: tema,
            value: 'Tema número ${i.toRadixString(36)}zz$i',
            createdAt: now,
          ),
      ]);
    });

    await pumpScreen(tester);

    // Sin uso los 2.000: la pestaña los cuenta...
    expect(find.text(es.vocabularyTabUnused(2000)), findsOneWidget);
    await openTab(tester, es.vocabularyTabUnused(2000));
    // ...pero la lista es perezosa: solo construye lo que se ve.
    expect(find.byType(CheckboxListTile).evaluate().length, lessThan(60));
    expect(find.byType(CheckboxListTile), findsWidgets);
  });
}
