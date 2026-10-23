import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/library_view_mode.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_query_notifier.dart';
import 'package:sinapsis/features/library/presentation/screens/library_screen.dart';
import 'package:sinapsis/features/library/presentation/screens/unsorted_items_screen.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// Lo que quedó sin tema (F37, paso 5): la tarjeta de la Biblioteca que lo
/// cuenta, la lista para ordenarlo de a varios y la columna del tablero.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  Future<String> createSpace(String name) async =>
      (await harness.container
              .read(organizeRepositoryProvider)
              .createSpace(name))
          .getRight()
          .toNullable()!
          .id;

  Future<List<KnowledgeItem>> allItems() async =>
      (await harness.container
              .read(libraryRepositoryProvider)
              .list(const LibraryQuery()))
          .getRight()
          .toNullable()!;

  Future<KnowledgeItem> byTitle(String title) async =>
      (await allItems()).firstWhere((item) => item.title == title);

  Future<void> putIn(String title, Set<String> spaceIds) async {
    await harness.container
        .read(libraryRepositoryProvider)
        .setSpaces(itemIds: [(await byTitle(title)).id], spaceIds: spaceIds);
  }

  Finder card() => find.byKey(const ValueKey('unsorted-items'));

  group('la tarjeta de la Biblioteca', () {
    testWidgets('cuenta lo que no tiene tema y lleva a la lista para '
        'ordenarlo', (tester) async {
      await harness.capture('Uno');
      await harness.capture('Dos');
      await putIn('Dos', {await createSpace('Roma')});
      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: card(),
          matching: find.text(es.libraryUnsortedTitle(1)),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text(es.libraryUnsortedAction));
      await tester.pumpAndSettle();

      expect(find.byType(UnsortedItemsScreen), findsOneWidget);
      expect(find.widgetWithText(CheckboxListTile, 'Uno'), findsOneWidget);
      expect(find.widgetWithText(CheckboxListTile, 'Dos'), findsNothing);
    });

    testWidgets('desaparece sola cuando no queda nada sin tema', (
      tester,
    ) async {
      await harness.capture('Uno');
      await tester.pumpWidget(harness.wrap(const LibraryScreen()));
      await tester.pumpAndSettle();
      expect(card(), findsOneWidget);

      await putIn('Uno', {await createSpace('Roma')});
      await tester.pumpAndSettle();

      expect(card(), findsNothing);
    });

    testWidgets('con un filtro puesto no aparece: el número no sería de lo '
        'que se está mirando', (tester) async {
      await harness.capture('Uno');
      await harness.capture('Dos');
      final roma = await createSpace('Roma');
      await putIn('Dos', {roma});
      await tester.pumpWidget(harness.wrap(const LibraryScreen()));
      await tester.pumpAndSettle();
      expect(card(), findsOneWidget);

      harness.container
          .read(libraryQueryNotifierProvider.notifier)
          .selectSpace(roma);
      await tester.pumpAndSettle();

      expect(card(), findsNothing);
    });
  });

  group('el tablero', () {
    Future<void> showKanban(WidgetTester tester) async {
      await tester.pumpWidget(harness.wrap(const LibraryScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<LibraryViewMode>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.libraryViewKanban));
      await tester.pumpAndSettle();
    }

    testWidgets('la columna «Sin clasificar» está mientras quede algo sin '
        'tema, y después no', (tester) async {
      await harness.capture('Uno');
      final roma = await createSpace('Roma');
      await showKanban(tester);
      expect(find.text(es.detailSpaceNone), findsOneWidget);

      await putIn('Uno', {roma});
      await tester.pumpAndSettle();

      expect(find.text(es.detailSpaceNone), findsNothing);
      expect(find.text('Roma'), findsOneWidget);
    });
  });

  group('la lista para ordenar', () {
    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.pumpWidget(harness.wrap(const UnsortedItemsScreen()));
      await tester.pumpAndSettle();
    }

    Finder row(String title) => find.widgetWithText(CheckboxListTile, title);

    Future<void> tickInSheet(WidgetTester tester, String name) async {
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.widgetWithText(CheckboxListTile, name),
        ),
      );
      await tester.pumpAndSettle();
    }

    FilledButton chooseButton(WidgetTester tester) =>
        tester.widget<FilledButton>(
          find.widgetWithIcon(FilledButton, Icons.folder_outlined),
        );

    testWidgets('sin nada marcado no se puede elegir', (tester) async {
      await harness.capture('Uno');
      await pumpScreen(tester);

      expect(chooseButton(tester).onPressed, isNull);
      expect(find.text(es.unsortedChoose(0)), findsOneWidget);

      await tester.tap(row('Uno'));
      await tester.pumpAndSettle();

      expect(chooseButton(tester).onPressed, isNotNull);
      expect(find.text(es.unsortedChoose(1)), findsOneWidget);
    });

    testWidgets('a los marcados les pone los temas elegidos, salen de la '
        'lista y avisa; los demás quedan', (tester) async {
      await harness.capture('Uno');
      await harness.capture('Dos');
      await harness.capture('Tres');
      final roma = await createSpace('Roma');
      final arte = await createSpace('Arte');
      await pumpScreen(tester);

      await tester.tap(row('Uno'));
      await tester.tap(row('Dos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.unsortedChoose(2)));
      await tester.pumpAndSettle();
      await tickInSheet(tester, 'Roma');
      await tickInSheet(tester, 'Arte');
      await tester.tap(find.text(es.spacesPickerDone));
      await tester.pumpAndSettle();

      expect((await byTitle('Uno')).spaceIds, {roma, arte});
      expect((await byTitle('Dos')).spaceIds, {roma, arte});
      expect((await byTitle('Tres')).spaceIds, isEmpty);
      expect(row('Uno'), findsNothing);
      expect(row('Dos'), findsNothing);
      expect(row('Tres'), findsOneWidget);
      expect(find.textContaining(es.unsortedDone(2, '')), findsOneWidget);
      // Lo que se ordenó ya no cuenta como marcado.
      expect(find.text(es.unsortedChoose(0)), findsOneWidget);
    });

    testWidgets('«Marcar todos» y, al ordenar lo último, la lista vacía lo '
        'dice', (tester) async {
      await harness.capture('Uno');
      await harness.capture('Dos');
      await createSpace('Roma');
      await pumpScreen(tester);

      await tester.tap(find.text(es.unsortedSelectAll));
      await tester.pumpAndSettle();
      expect(find.text(es.unsortedChoose(2)), findsOneWidget);
      expect(find.text(es.unsortedSelectNone), findsOneWidget);

      await tester.tap(find.text(es.unsortedChoose(2)));
      await tester.pumpAndSettle();
      await tickInSheet(tester, 'Roma');
      await tester.tap(find.text(es.spacesPickerDone));
      await tester.pumpAndSettle();

      expect(find.text(es.unsortedEmptyTitle), findsOneWidget);
      expect(find.text(es.unsortedSelectAll), findsNothing);
    });

    testWidgets('lo ordenado deja de estar marcado: si vuelve a la lista '
        '—se borró su tema—, vuelve sin marcar', (tester) async {
      await harness.capture('Uno');
      final roma = await createSpace('Roma');
      await pumpScreen(tester);

      await tester.tap(row('Uno'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.unsortedChoose(1)));
      await tester.pumpAndSettle();
      await tickInSheet(tester, 'Roma');
      await tester.tap(find.text(es.spacesPickerDone));
      await tester.pumpAndSettle();
      expect(row('Uno'), findsNothing);

      await harness.container
          .read(organizeRepositoryProvider)
          .deleteSpace(roma);
      await tester.pumpAndSettle();

      expect(row('Uno'), findsOneWidget);
      expect(tester.widget<CheckboxListTile>(row('Uno')).value, isFalse);
      expect(find.text(es.unsortedChoose(0)), findsOneWidget);
    });

    testWidgets('cerrar la hoja sin elegir no toca nada', (tester) async {
      await harness.capture('Uno');
      await createSpace('Roma');
      await pumpScreen(tester);

      await tester.tap(row('Uno'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.unsortedChoose(1)));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(400, 20));
      await tester.pumpAndSettle();

      expect((await byTitle('Uno')).spaceIds, isEmpty);
      expect(row('Uno'), findsOneWidget);
      expect(find.text(es.unsortedChoose(1)), findsOneWidget);
    });
  });
}
