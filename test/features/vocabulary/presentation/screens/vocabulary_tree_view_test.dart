import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/features/vocabulary/presentation/screens/vocabulary_category_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// El árbol del vocabulario en la pantalla de una categoría (F13): verlo,
/// desplegarlo, y mover una rama por el menú, arrastrando y con el teclado —
/// siempre con confirmación y con «Deshacer»—.
///
/// Contra SQLite real: lo que importa es lo que queda en la base.
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

  Future<void> addValue(
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

  /// Roma ─ República ─ Gracos, Roma ─ Imperio, y Grecia sola.
  Future<void> seed() async {
    await addValue('roma', 'Roma');
    await addValue('republica', 'República', parent: 'roma', depth: 1);
    await addValue('gracos', 'Gracos', parent: 'republica', depth: 2);
    await addValue('imperio', 'Imperio', parent: 'roma', depth: 1);
    await addValue('grecia', 'Grecia');
  }

  Future<void> pump(WidgetTester tester, {String? definitionId}) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness.wrap(
        VocabularyCategoryScreen(definitionId: definitionId ?? tema),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> showTree(WidgetTester tester) async {
    await tester.tap(find.text(es.vocabularyViewTree));
    await tester.pumpAndSettle();
  }

  Finder node(String id) => find.byKey(ValueKey('vocabulary-node-$id'));

  Future<Map<String, (String?, int)>> tree() async => {
    for (final r in await db.select(db.propertyValues).get())
      if (r.definitionId == tema) r.id: (r.parentId, r.depth),
  };

  Future<void> openMenu(WidgetTester tester, String id) async {
    await tester.tap(
      find.descendant(
        of: node(id),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> expand(WidgetTester tester, String id) async {
    await tester.tap(
      find.descendant(of: node(id), matching: find.byIcon(Icons.chevron_right)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('el árbol arranca plegado: solo las raíces', (tester) async {
    await seed();
    await pump(tester);

    await showTree(tester);

    expect(node('roma'), findsOneWidget);
    expect(node('grecia'), findsOneWidget);
    expect(node('republica'), findsNothing);
    expect(find.textContaining(es.vocabularySubtopics(2)), findsOneWidget);
  });

  testWidgets('desplegar muestra los subtemas, con sangría', (tester) async {
    await seed();
    await pump(tester);
    await showTree(tester);

    await expand(tester, 'roma');
    await expand(tester, 'republica');

    expect(node('republica'), findsOneWidget);
    expect(node('imperio'), findsOneWidget);
    expect(node('gracos'), findsOneWidget);
    final republicaLeft = tester.getTopLeft(find.text('República')).dx;
    final gracosLeft = tester.getTopLeft(find.text('Gracos')).dx;
    final romaLeft = tester.getTopLeft(find.text('Roma')).dx;
    expect(republicaLeft, greaterThan(romaLeft));
    expect(gracosLeft, greaterThan(republicaLeft));
  });

  testWidgets('plegar de nuevo los oculta', (tester) async {
    await seed();
    await pump(tester);
    await showTree(tester);
    await expand(tester, 'roma');

    await tester.tap(
      find.descendant(
        of: node('roma'),
        matching: find.byIcon(Icons.expand_more),
      ),
    );
    await tester.pumpAndSettle();

    expect(node('republica'), findsNothing);
  });

  testWidgets('una categoría que no es de texto no ofrece el árbol', (
    tester,
  ) async {
    final fecha = await (db.select(
      db.propertyDefinitions,
    )..where((d) => d.name.equals('Fecha del hecho'))).getSingle();
    await addValue('f1', '44 a.C.', definitionId: fecha.id);
    await pump(tester, definitionId: fecha.id);

    expect(find.text(es.vocabularyViewTree), findsNothing);
  });

  testWidgets('buscando, se vuelve a la lista plana: encuentra el valor donde '
      'esté', (tester) async {
    await seed();
    await pump(tester);
    await showTree(tester);

    await tester.enterText(find.byType(TextField), 'gracos');
    await tester.pumpAndSettle();

    expect(find.text('Gracos'), findsOneWidget);
    expect(node('roma'), findsNothing);
  });

  group('mover por el menú', () {
    testWidgets('«Mover bajo…» ofrece solo los destinos que se pueden', (
      tester,
    ) async {
      await seed();
      await pump(tester);
      await showTree(tester);
      await expand(tester, 'roma');

      await openMenu(tester, 'republica');
      await tester.tap(find.text(es.vocabularyMoveUnder));
      await tester.pumpAndSettle();

      // Ni él, ni su propio padre (ya está ahí), ni un subtema suyo.
      expect(find.byKey(const ValueKey('vocabulary-target-grecia')), findsOne);
      expect(find.byKey(const ValueKey('vocabulary-target-imperio')), findsOne);
      expect(
        find.byKey(const ValueKey('vocabulary-target-republica')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('vocabulary-target-gracos')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('vocabulary-target-roma')),
        findsNothing,
      );
    });

    testWidgets('elegir un destino pide confirmación y mueve toda la rama', (
      tester,
    ) async {
      await seed();
      await pump(tester);
      await showTree(tester);
      await expand(tester, 'roma');

      await openMenu(tester, 'republica');
      await tester.tap(find.text(es.vocabularyMoveUnder));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('vocabulary-target-grecia')));
      await tester.pumpAndSettle();

      // Dice cuánto mueve, y todavía no cambió nada.
      expect(find.text(es.vocabularyMoveConfirmTitle), findsOneWidget);
      expect(
        find.text(es.vocabularyMoveConfirmBody(2, 'República', 'Grecia')),
        findsOneWidget,
      );
      expect((await tree())['republica'], ('roma', 1));

      await tester.tap(find.text(es.vocabularyMoveConfirmAction));
      await tester.pumpAndSettle();

      expect(await tree(), {
        'roma': (null, 0),
        'republica': ('grecia', 1),
        'gracos': ('republica', 2),
        'imperio': ('roma', 1),
        'grecia': (null, 0),
      });
      expect(find.text(es.vocabularyOperationMoved(2, 'República')), findsOne);
    });

    testWidgets('cancelar la confirmación no cambia nada', (tester) async {
      await seed();
      await pump(tester);
      await showTree(tester);
      await expand(tester, 'roma');
      final before = await tree();

      await openMenu(tester, 'imperio');
      await tester.tap(find.text(es.vocabularyMoveUnder));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('vocabulary-target-grecia')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(await tree(), before);
    });

    testWidgets('«Deshacer» del aviso devuelve la rama a donde estaba', (
      tester,
    ) async {
      await seed();
      await pump(tester);
      await showTree(tester);
      await expand(tester, 'roma');
      final before = await tree();
      await openMenu(tester, 'republica');
      await tester.tap(find.text(es.vocabularyMoveUnder));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('vocabulary-target-grecia')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.vocabularyMoveConfirmAction));
      await tester.pumpAndSettle();

      await tester.tap(find.text(es.vocabularyUndoAction));
      await tester.pumpAndSettle();

      expect(await tree(), before);
    });

    testWidgets('«Llevar al primer nivel» solo está en lo que tiene padre', (
      tester,
    ) async {
      await seed();
      await pump(tester);
      await showTree(tester);
      await expand(tester, 'roma');

      await openMenu(tester, 'roma');
      expect(find.text(es.vocabularyMakeRoot), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      await openMenu(tester, 'republica');
      await tester.tap(find.text(es.vocabularyMakeRoot));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.vocabularyMoveConfirmAction));
      await tester.pumpAndSettle();

      expect((await tree())['republica'], (null, 0));
      expect((await tree())['gracos'], ('republica', 1));
    });
  });

  testWidgets('arrastrar una fila sobre otra la mueve, con confirmación', (
    tester,
  ) async {
    await seed();
    await pump(tester);
    await showTree(tester);
    await expand(tester, 'roma');

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Imperio')),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveTo(tester.getCenter(find.text('Grecia')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      find.text(es.vocabularyMoveConfirmBody(1, 'Imperio', 'Grecia')),
      findsOneWidget,
    );
    await tester.tap(find.text(es.vocabularyMoveConfirmAction));
    await tester.pumpAndSettle();

    expect((await tree())['imperio'], ('grecia', 1));
  });

  testWidgets('arrastrar a la franja de arriba lo lleva al primer nivel', (
    tester,
  ) async {
    await seed();
    await pump(tester);
    await showTree(tester);
    await expand(tester, 'roma');

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Imperio')),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    final strip = find.byKey(const ValueKey('vocabulary-drop-root'));
    expect(strip, findsOneWidget);
    await gesture.moveTo(tester.getCenter(strip));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text(es.vocabularyMoveConfirmAction));
    await tester.pumpAndSettle();

    expect((await tree())['imperio'], (null, 0));
  });

  testWidgets('con el teclado: la flecha derecha despliega y la izquierda '
      'pliega', (tester) async {
    await seed();
    await pump(tester);
    await showTree(tester);

    // El foco en la fila, como lo dejaría Tab.
    Focus.of(tester.element(node('roma'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(node('republica'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    expect(node('republica'), findsNothing);
  });
}
