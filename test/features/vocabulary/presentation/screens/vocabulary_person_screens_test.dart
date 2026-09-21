import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/features/vocabulary/presentation/screens/vocabulary_category_screen.dart';
import 'package:sinapsis/features/vocabulary/presentation/screens/vocabulary_value_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/item_rows.dart';
import '../../../../support/library_harness.dart';

/// Las pantallas del vocabulario con la categoría de autores (F15): agregar y
/// editar una persona con su apellido y su nombre, y ver sus obras.
///
/// Contra SQLite real. Las pantallas se montan sueltas, sin router: lo que
/// navega —tocar una obra— lo prueba el detalle de cada elemento.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late AppDatabase db;

  final now = DateTime(2026, 9, 21, 10);

  setUp(() async {
    harness = await LibraryHarness.create();
    db = harness.database;
  });

  Future<String> authorCategory() async => (await (db.select(
    db.propertyDefinitions,
  )..where((d) => d.name.equals('Autor'))).getSingle()).id;

  Future<void> person(
    String id,
    String label, {
    String? family,
    String? given,
  }) async {
    await db
        .into(db.propertyValues)
        .insert(
          PropertyValuesCompanion.insert(
            id: id,
            definitionId: await authorCategory(),
            value: label,
            createdAt: now,
            nameFamily: Value(family),
            nameGiven: Value(given),
          ),
        );
  }

  Future<void> work(
    String workId,
    String personId, {
    String? title,
    ContributorRole role = ContributorRole.author,
    int position = 0,
  }) async {
    await insertItemRows(
      db,
      id: workId,
      title: title ?? 'Obra $workId',
      createdAt: now,
    );
    await db
        .into(db.sourceReferences)
        .insert(SourceReferencesCompanion.insert(itemId: workId));
    await db
        .into(db.sourceContributors)
        .insert(
          SourceContributorsCompanion.insert(
            itemId: workId,
            propertyValueId: personId,
            role: role,
            position: position,
          ),
        );
    await db
        .into(db.itemPropertyValues)
        .insert(
          ItemPropertyValuesCompanion.insert(
            itemId: workId,
            propertyValueId: personId,
            origin: const Value(ItemPropertyOrigin.reference),
          ),
        );
  }

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrap(screen));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  group('la categoría de autores', () {
    testWidgets('tiene el botón para agregar un autor', (tester) async {
      await pump(
        tester,
        VocabularyCategoryScreen(definitionId: await authorCategory()),
      );

      expect(find.byTooltip(es.vocabularyAddPersonTitle), findsOneWidget);
    });

    testWidgets('una categoría de texto no lo tiene', (tester) async {
      await pump(
        tester,
        VocabularyCategoryScreen(definitionId: await temaDefinitionId(db)),
      );

      expect(find.byTooltip(es.vocabularyAddPersonTitle), findsNothing);
    });

    testWidgets(
      'agregar un autor con su apellido y su nombre lo crea y avisa',
      (tester) async {
        await pump(
          tester,
          VocabularyCategoryScreen(definitionId: await authorCategory()),
        );

        await tester.tap(find.byTooltip(es.vocabularyAddPersonTitle));
        await tester.pumpAndSettle();
        await tester.enterText(field(es.personFamilyLabel), 'García Márquez');
        await tester.enterText(field(es.personGivenLabel), 'Gabriel');
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, es.personDialogSave));
        await tester.pumpAndSettle();

        // La lista y el aviso —con su «Deshacer»— dicen quién se agregó.
        expect(find.text('García Márquez, Gabriel'), findsWidgets);
        expect(
          find.text(
            es.vocabularyOperationPersonAdded('García Márquez, Gabriel'),
          ),
          findsOneWidget,
        );
        expect(find.text(es.vocabularyUndoAction), findsOneWidget);
        final saved = await db.select(db.propertyValues).getSingle();
        expect(
          (saved.nameFamily, saved.nameGiven),
          ('García Márquez', 'Gabriel'),
        );
      },
    );

    testWidgets('uno que ya existe no se duplica y lo dice', (tester) async {
      await person(
        'gabo',
        'García Márquez, Gabriel',
        family: 'García Márquez',
        given: 'Gabriel',
      );
      await pump(
        tester,
        VocabularyCategoryScreen(definitionId: await authorCategory()),
      );

      await tester.tap(find.byTooltip(es.vocabularyAddPersonTitle));
      await tester.pumpAndSettle();
      // Sin acentos: es la misma persona.
      await tester.enterText(field(es.personFamilyLabel), 'Garcia Marquez');
      await tester.enterText(field(es.personGivenLabel), 'Gabriel');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, es.personDialogSave));
      await tester.pumpAndSettle();

      // Un fallo de validación: el aviso general, y nada creado.
      expect(find.text(es.globalErrorValidation), findsOneWidget);
      expect(await db.select(db.propertyValues).get(), hasLength(1));
    });

    testWidgets('cancelar no crea nada', (tester) async {
      await pump(
        tester,
        VocabularyCategoryScreen(definitionId: await authorCategory()),
      );

      await tester.tap(find.byTooltip(es.vocabularyAddPersonTitle));
      await tester.pumpAndSettle();
      await tester.enterText(field(es.personFamilyLabel), 'Borges');
      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      expect(await db.select(db.propertyValues).get(), isEmpty);
    });
  });

  group('una persona en detalle', () {
    testWidgets('sus obras, con su rol, por título', (tester) async {
      await person(
        'gabo',
        'García Márquez, Gabriel',
        family: 'García Márquez',
        given: 'Gabriel',
      );
      await work('b', 'gabo', title: 'El otoño del patriarca');
      await work(
        'a',
        'gabo',
        title: 'Cien años de soledad',
        role: ContributorRole.translator,
      );
      await pump(
        tester,
        VocabularyValueScreen(
          definitionId: await authorCategory(),
          valueId: 'gabo',
        ),
      );

      expect(find.text(es.vocabularyWorksTitle), findsOneWidget);
      expect(find.text('Cien años de soledad'), findsOneWidget);
      expect(find.text('El otoño del patriarca'), findsOneWidget);
      expect(find.text(es.contributorRoleTranslator), findsOneWidget);
      expect(find.text(es.contributorRoleAuthor), findsOneWidget);
    });

    testWidgets('sin obras lo dice', (tester) async {
      await person(
        'gabo',
        'García Márquez, Gabriel',
        family: 'García Márquez',
        given: 'Gabriel',
      );
      await pump(
        tester,
        VocabularyValueScreen(
          definitionId: await authorCategory(),
          valueId: 'gabo',
        ),
      );

      expect(find.text(es.vocabularyWorksEmpty), findsOneWidget);
    });

    testWidgets('una obra en la papelera no figura', (tester) async {
      await person(
        'gabo',
        'García Márquez, Gabriel',
        family: 'García Márquez',
        given: 'Gabriel',
      );
      await work('a', 'gabo', title: 'Viva');
      await work('b', 'gabo', title: 'Borrada', position: 1);
      await db.customStatement(
        'UPDATE item SET deleted_at = ${now.millisecondsSinceEpoch ~/ 1000} '
        "WHERE id = 'b'",
      );
      await pump(
        tester,
        VocabularyValueScreen(
          definitionId: await authorCategory(),
          valueId: 'gabo',
        ),
      );

      expect(find.text('Viva'), findsOneWidget);
      expect(find.text('Borrada'), findsNothing);
    });

    testWidgets('un valor de texto no tiene obras', (tester) async {
      final tema = await temaDefinitionId(db);
      await db
          .into(db.propertyValues)
          .insert(
            PropertyValuesCompanion.insert(
              id: 'roma',
              definitionId: tema,
              value: 'Roma',
              createdAt: now,
            ),
          );
      await pump(
        tester,
        VocabularyValueScreen(definitionId: tema, valueId: 'roma'),
      );

      expect(find.text(es.vocabularyWorksTitle), findsNothing);
    });

    testWidgets('editar abre el nombre partido, y guarda el nuevo', (
      tester,
    ) async {
      await person(
        'gabo',
        'García Márquez, G.',
        family: 'García Márquez',
        given: 'G.',
      );
      await pump(
        tester,
        VocabularyValueScreen(
          definitionId: await authorCategory(),
          valueId: 'gabo',
        ),
      );

      await tester.tap(find.byTooltip(es.commonRename));
      await tester.pumpAndSettle();
      // El diálogo es el de la persona, con sus campos ya cargados.
      expect(find.text(es.vocabularyEditPersonTitle), findsOneWidget);
      expect(
        tester.widget<TextField>(field(es.personGivenLabel)).controller!.text,
        'G.',
      );
      await tester.enterText(field(es.personGivenLabel), 'Gabriel');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, es.personDialogSave));
      await tester.pumpAndSettle();

      final saved = await (db.select(
        db.propertyValues,
      )..where((v) => v.id.equals('gabo'))).getSingle();
      expect(saved.value, 'García Márquez, Gabriel');
      expect(saved.nameGiven, 'Gabriel');
      expect(
        find.text(es.vocabularyOperationRenamed('García Márquez, Gabriel')),
        findsOneWidget,
      );
    });

    testWidgets('una persona que nadie partió abre con todo el nombre como '
        'apellido, sin adivinar', (tester) async {
      await person('gabo', 'Gabriel García Márquez');
      await pump(
        tester,
        VocabularyValueScreen(
          definitionId: await authorCategory(),
          valueId: 'gabo',
        ),
      );

      await tester.tap(find.byTooltip(es.commonRename));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(field(es.personFamilyLabel)).controller!.text,
        'Gabriel García Márquez',
      );
      expect(
        tester.widget<TextField>(field(es.personGivenLabel)).controller!.text,
        isEmpty,
      );
    });

    testWidgets('un valor de texto se renombra con el diálogo de siempre', (
      tester,
    ) async {
      final tema = await temaDefinitionId(db);
      await db
          .into(db.propertyValues)
          .insert(
            PropertyValuesCompanion.insert(
              id: 'roma',
              definitionId: tema,
              value: 'Roma',
              createdAt: now,
            ),
          );
      await pump(
        tester,
        VocabularyValueScreen(definitionId: tema, valueId: 'roma'),
      );

      await tester.tap(find.byTooltip(es.commonRename));
      await tester.pumpAndSettle();

      expect(find.text(es.vocabularyRenameTitle), findsOneWidget);
      expect(field(es.personFamilyLabel), findsNothing);
    });
  });
}
