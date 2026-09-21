import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/graph/domain/services/relation_suggestion_service.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/item_rows.dart';
import '../../../../support/library_harness.dart';

/// Lo que el grafo del mapa hace con los vínculos (F14): agregar uno entre dos
/// elementos cualquiera y pedirle a la IA que sugiera entre los de un tema. Son
/// las dos acciones que tenía el grafo completo que el mapa reemplazó, contra
/// SQLite real y el router real.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late AppDatabase db;
  late String tema;
  final now = DateTime(2026, 9, 21, 10);

  /// Si el modelo de lenguaje está descargado, para el arnés de cada prueba.
  var modelReady = false;

  setUp(() async {
    harness = await LibraryHarness.create(chatModelReady: modelReady);
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

  Future<void> item(String id, List<String> values) async {
    await insertItemRows(
      db,
      id: id,
      title: 'Fuente $id',
      createdAt: DateTime(2026, 8, 10),
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

  Future<void> relate(String id, String from, String to, RelationKind kind) =>
      db
          .into(db.relations)
          .insert(
            RelationsCompanion.insert(
              id: id,
              fromItemId: from,
              toItemId: to,
              kind: kind,
              createdAt: now,
            ),
          );

  /// Roma tiene tres fuentes —las dos primeras ya vinculadas entre sí—; Grecia
  /// comparte dos con Roma; Egipto tiene una, suelta, y fuera de los otros dos.
  Future<void> seed() async {
    await value('roma', 'Roma');
    await value('grecia', 'Grecia');
    await value('egipto', 'Egipto');
    await item('s1', ['roma', 'grecia']);
    await item('s2', ['roma', 'grecia']);
    await item('s3', ['roma']);
    await item('s4', ['egipto']);
    await relate('r1', 's1', 's2', RelationKind.relatedTo);
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();
    harness.goTo(RoutePaths.graph);
    await tester.pumpAndSettle();
    await tester.tap(find.text(es.mapViewGraph));
    await tester.pumpAndSettle();
  }

  Finder node(String key) => find.byKey(ValueKey('map-graph-node-$key'));
  final addRelation = find.byKey(const ValueKey('map-graph-add-relation'));
  final aiSuggest = find.byKey(const ValueKey('map-graph-ai-suggest'));

  /// Un elemento de la lista de un diálogo, no el del mapa que queda detrás.
  Finder inDialog(String text) =>
      find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Del panorama a los elementos de Roma.
  Future<void> openRomaItems(WidgetTester tester) async {
    await tapAndSettle(tester, node('overview:0'));
    await tapAndSettle(tester, node('topic:roma'));
    await tapAndSettle(
      tester,
      find.byKey(const ValueKey('map-graph-action-items')),
    );
  }

  Future<List<RelationRow>> relations() => db.select(db.relations).get();

  group('agregar vínculo', () {
    testWidgets('desde el panorama vincula dos elementos cualquiera, aunque '
        'sean de temas distintos', (tester) async {
      await seed();
      await pump(tester);

      await tapAndSettle(tester, addRelation);
      // El primero, y el segundo sin poder repetirlo.
      await tapAndSettle(tester, inDialog('Fuente s3'));
      expect(inDialog('Fuente s3'), findsNothing);
      await tapAndSettle(tester, inDialog('Fuente s4'));
      await tapAndSettle(tester, find.text(es.pickRelationConfirm));

      final created = (await relations()).where((r) => r.id != 'r1').toList();
      expect(created, hasLength(1));
      expect(created.single.fromItemId, 's3');
      expect(created.single.toItemId, 's4');
      expect(created.single.kind, RelationKind.relatedTo);
    });

    testWidgets('está a mano también con los elementos de un tema a la vista', (
      tester,
    ) async {
      await seed();
      await pump(tester);
      await openRomaItems(tester);

      await tapAndSettle(tester, addRelation);
      await tapAndSettle(tester, inDialog('Fuente s3'));
      await tapAndSettle(tester, inDialog('Fuente s1'));
      await tapAndSettle(tester, find.text(es.pickRelationConfirm));

      expect(
        (await relations()).where(
          (r) => r.fromItemId == 's3' && r.toItemId == 's1',
        ),
        hasLength(1),
      );
    });

    testWidgets('dejarlo a medias no crea nada', (tester) async {
      await seed();
      await pump(tester);

      await tapAndSettle(tester, addRelation);
      await tapAndSettle(tester, inDialog('Fuente s3'));
      await tapAndSettle(tester, find.text(es.commonCancel));

      expect(await relations(), hasLength(1));
    });

    testWidgets('si el vínculo ya existe, lo dice', (tester) async {
      await seed();
      await pump(tester);

      await tapAndSettle(tester, addRelation);
      await tapAndSettle(tester, inDialog('Fuente s1'));
      await tapAndSettle(tester, inDialog('Fuente s2'));
      await tapAndSettle(tester, find.text(es.pickRelationConfirm));

      expect(find.text(es.globalErrorValidation), findsOneWidget);
      expect(await relations(), hasLength(1));
    });
  });

  group('sugerir vínculos con IA', () {
    testWidgets('solo se ofrece con los elementos de un tema a la vista', (
      tester,
    ) async {
      await seed();
      await pump(tester);
      expect(aiSuggest, findsNothing);

      // En los temas de una comunidad, todavía no.
      await tapAndSettle(tester, node('overview:0'));
      expect(aiSuggest, findsNothing);

      await tapAndSettle(tester, node('topic:roma'));
      await tapAndSettle(
        tester,
        find.byKey(const ValueKey('map-graph-action-items')),
      );
      expect(aiSuggest, findsOneWidget);
    });

    testWidgets('con un solo elemento no hay entre qué sugerir', (
      tester,
    ) async {
      await seed();
      await pump(tester);

      // Egipto solo tiene la fuente s4.
      await tapAndSettle(tester, node('overview:1'));
      await tapAndSettle(tester, node('topic:egipto'));
      await tapAndSettle(
        tester,
        find.byKey(const ValueKey('map-graph-action-items')),
      );

      expect(node('item:s4'), findsOneWidget);
      expect(aiSuggest, findsNothing);
    });

    testWidgets('sin el modelo descargado, avisa antes de pedir nada', (
      tester,
    ) async {
      await seed();
      await pump(tester);
      await openRomaItems(tester);

      await tapAndSettle(tester, aiSuggest);

      expect(find.text(es.graphAiModelRequiredTitle), findsOneWidget);
      expect(harness.relationSuggestionService.requests, isEmpty);
    });

    group('con el modelo listo', () {
      setUpAll(() => modelReady = true);
      tearDownAll(() => modelReady = false);

      testWidgets('el punto de partida se elige entre los elementos del tema, '
          'no entre los de toda la biblioteca', (tester) async {
        await seed();
        await pump(tester);
        await openRomaItems(tester);

        await tapAndSettle(tester, aiSuggest);

        expect(inDialog('Fuente s1'), findsOneWidget);
        expect(inDialog('Fuente s2'), findsOneWidget);
        expect(inDialog('Fuente s3'), findsOneWidget);
        // s4 es de Egipto: fuera del tema, no se puede elegir.
        expect(inDialog('Fuente s4'), findsNothing);
      });

      testWidgets('los candidatos son los del tema que aún no están vinculados '
          'con el de partida', (tester) async {
        await seed();
        await pump(tester);
        await openRomaItems(tester);

        await tapAndSettle(tester, aiSuggest);
        await tapAndSettle(tester, inDialog('Fuente s1'));

        // s2 ya está vinculado con s1 y s4 no es del tema: solo queda s3.
        expect(harness.relationSuggestionService.requests, hasLength(1));
        final request = harness.relationSuggestionService.requests.single;
        expect(request.seedTitle, 'Fuente s1');
        expect(request.candidateCount, 1);
      });

      testWidgets('muestra lo que la IA propone y lo guarda al confirmar, con '
          'su razón', (tester) async {
        harness.relationSuggestionService.suggestions = const [
          RelationSuggestion(
            itemId: 's3',
            kind: RelationKind.cites,
            reason: 'Hablan de lo mismo',
          ),
        ];
        await seed();
        await pump(tester);
        await openRomaItems(tester);

        await tapAndSettle(tester, aiSuggest);
        await tapAndSettle(tester, inDialog('Fuente s1'));

        expect(inDialog('Fuente s3'), findsOneWidget);
        expect(find.text('Hablan de lo mismo'), findsOneWidget);

        await tapAndSettle(tester, find.text(es.graphAiDialogConfirm(1)));

        final created = (await relations()).where((r) => r.id != 'r1').toList();
        expect(created, hasLength(1));
        expect(created.single.fromItemId, 's1');
        expect(created.single.toItemId, 's3');
        expect(created.single.kind, RelationKind.cites);
        expect(created.single.note, 'Hablan de lo mismo');
        expect(find.text(es.graphRelationsAdded(1)), findsOneWidget);
      });
    });
  });
}
