import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/features/inbox/presentation/screens/inbox_screen.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';
import 'package:sinapsis/features/suggestions/presentation/widgets/property_suggestion_group_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// La oferta sobre la tarjeta de la Bandeja (F12): «14 elementos más parecen
/// ser `Región: Roma`». Quien está triando una fuente por vez puede revisar el
/// grupo entero sin salir de la Bandeja, y al volver la tarjeta sigue en su
/// lugar.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  var counter = 0;

  setUp(() async {
    harness = await LibraryHarness.create();
    counter = 0;
  });

  /// Una fuente lista para triar. Las que se guardan primero son las primeras
  /// del mazo.
  Future<String> seedSource(String title) async {
    final n = counter++;
    final now = DateTime(2026, 9, 18, 10).add(Duration(minutes: n));
    final id = 'item-${n.toString().padLeft(3, '0')}';
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: id,
            title: title,
            source: Source(
              id: 'src-$n',
              kind: SourceKind.webPage,
              capturedAt: now,
              url: 'https://ejemplo.org/$n',
            ),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<String> suggest(
    String itemId, {
    String category = 'Región',
    String value = 'Roma',
  }) async {
    final definition =
        (await harness.container
                .read(organizeRepositoryProvider)
                .getOrCreatePropertyDefinition(category))
            .getRight()
            .toNullable()!;
    return (await harness.container
            .read(suggestionRepositoryProvider)
            .createPropertySuggestion(
              targetItemId: itemId,
              definitionId: definition.id,
              definitionName: category,
              value: value,
              isNewValue: true,
            ))
        .getRight()
        .toNullable()!
        .id;
  }

  Future<void> pumpInbox(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrap(const InboxScreen()));
    await tester.pumpAndSettle();
  }

  Future<ItemState> stateOf(String id) async => (await (harness.database.select(
    harness.database.knowledgeEntries,
  )..where((e) => e.id.equals(id))).getSingle()).state;

  Future<Map<String, SuggestionStatus>> statuses() async => {
    for (final s
        in await harness.database.select(harness.database.suggestions).get())
      s.targetItemId: s.status,
  };

  Future<List<String>> propertyOwners() async => [
    for (final row
        in await harness.database
            .select(harness.database.itemPropertyValues)
            .get())
      row.itemId,
  ];

  Finder offer(int others, {String value = 'Roma'}) =>
      find.text(es.inboxSuggestionMore(others, 'Región', value));

  Finder sheet() => find.byType(PropertySuggestionGroupSheet);

  Finder row(String title) => find.widgetWithText(CheckboxListTile, title);

  group('la oferta', () {
    testWidgets('dice cuántos elementos más tienen la misma sugerencia', (
      tester,
    ) async {
      final a = await seedSource('A');
      final b = await seedSource('B');
      final c = await seedSource('C');
      for (final id in [a, b, c]) {
        await suggest(id);
      }

      await pumpInbox(tester);

      expect(offer(2), findsOneWidget);
    });

    testWidgets('con uno solo, «1 elemento más»', (tester) async {
      final a = await seedSource('A');
      final b = await seedSource('B');
      await suggest(a);
      await suggest(b);

      await pumpInbox(tester);

      expect(offer(1), findsOneWidget);
      expect(
        find.text('1 elemento más parece ser Región: Roma'),
        findsOneWidget,
      );
    });

    testWidgets('sin otros elementos con esa sugerencia no hay oferta', (
      tester,
    ) async {
      final a = await seedSource('A');
      await seedSource('B');
      await suggest(a);

      await pumpInbox(tester);

      expect(find.byType(FilterChip), findsOneWidget);
      expect(find.textContaining('más parece'), findsNothing);
      expect(find.textContaining('más parecen'), findsNothing);
    });

    testWidgets('«Roma», «roma» y «ROMA» son el mismo grupo; otra categoría, '
        'no', (tester) async {
      final a = await seedSource('A');
      final b = await seedSource('B');
      final c = await seedSource('C');
      final d = await seedSource('D');
      await suggest(a);
      await suggest(b, value: 'roma');
      await suggest(c, value: 'ROMA');
      await suggest(d, category: 'Época');

      await pumpInbox(tester);

      expect(offer(2), findsOneWidget);
    });

    testWidgets('sin sugerencias en la tarjeta no hay nada que ofrecer', (
      tester,
    ) async {
      await seedSource('A');
      final b = await seedSource('B');
      final c = await seedSource('C');
      await suggest(b);
      await suggest(c);

      await pumpInbox(tester);

      // La tarjeta de A no tiene sugerencias: lo de B y C no es de ella.
      expect(find.byType(FilterChip), findsNothing);
      expect(find.textContaining('más parecen'), findsNothing);
    });

    testWidgets('sigue ahí después de aceptar el chip de esta fuente', (
      tester,
    ) async {
      final a = await seedSource('A');
      final b = await seedSource('B');
      await suggest(a);
      await suggest(b);
      await pumpInbox(tester);

      await tester.tap(find.widgetWithText(FilterChip, 'Región: Roma'));
      await tester.pumpAndSettle();

      expect(await propertyOwners(), [a]);
      expect(offer(1), findsOneWidget);
    });
  });

  group('la hoja', () {
    Future<List<String>> threeWithRoma() async {
      final ids = [
        await seedSource('A'),
        await seedSource('B'),
        await seedSource('C'),
      ];
      for (final id in ids) {
        await suggest(id);
      }
      return ids;
    }

    testWidgets('se abre sobre la Bandeja con los demás elementos, sin nada '
        'marcado, y la tarjeta sigue debajo', (tester) async {
      await threeWithRoma();
      await pumpInbox(tester);

      await tester.tap(offer(2));
      await tester.pumpAndSettle();

      expect(sheet(), findsOneWidget);
      expect(find.byType(InboxScreen), findsOneWidget);
      // Los otros dos, no el de la tarjeta.
      expect(row('B'), findsOneWidget);
      expect(row('C'), findsOneWidget);
      expect(row('A'), findsNothing);
      // Nada marcado, y el lote acelera la confirmación, no la quita: la barra
      // de la hoja no aparece hasta marcar algo.
      expect(
        find.descendant(of: sheet(), matching: find.byType(FilledButton)),
        findsNothing,
      );
      expect(find.text(es.suggestionReviewHint), findsOneWidget);
    });

    testWidgets('aceptar aplica solo lo marcado, cierra la hoja y la Bandeja '
        'sigue en el mismo lugar', (tester) async {
      final ids = await threeWithRoma();
      await pumpInbox(tester);
      expect(find.text(es.inboxPendingCount(3)), findsOneWidget);

      await tester.tap(offer(2));
      await tester.pumpAndSettle();
      await tester.tap(row('B'));
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, es.suggestionReviewAccept(1)),
      );
      await tester.pumpAndSettle();

      expect(await propertyOwners(), [ids[1]]);
      expect(sheet(), findsNothing);
      // La misma tarjeta, la misma cola: nada cambió de estado ni de lugar.
      expect(find.byType(InboxScreen), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      expect(find.text(es.inboxPendingCount(3)), findsOneWidget);
      for (final id in ids) {
        expect(await stateOf(id), ItemState.processed);
      }
      // Y el aviso, con su «Deshacer», a la vista en la pantalla de abajo.
      expect(find.text(es.suggestionReviewAccepted(1)), findsOneWidget);
      expect(find.text(es.suggestionReviewUndo), findsOneWidget);
    });

    testWidgets('el deshacer del aviso revierte lo aceptado en la hoja', (
      tester,
    ) async {
      final ids = await threeWithRoma();
      await pumpInbox(tester);
      await tester.tap(offer(2));
      await tester.pumpAndSettle();
      await tester.tap(row('B'));
      await tester.tap(row('C'));
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, es.suggestionReviewAccept(2)),
      );
      await tester.pumpAndSettle();
      expect(await propertyOwners(), unorderedEquals([ids[1], ids[2]]));

      await tester.tap(find.text(es.suggestionReviewUndo));
      await tester.pumpAndSettle();

      expect(await propertyOwners(), isEmpty);
      expect((await statuses())[ids[1]], SuggestionStatus.pending);
      expect((await statuses())[ids[2]], SuggestionStatus.pending);
      // La oferta vuelve: los dos siguen pendientes.
      expect(offer(2), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('descartar las marcadas no aplica nada ni ofrece deshacer', (
      tester,
    ) async {
      final ids = await threeWithRoma();
      await pumpInbox(tester);
      await tester.tap(offer(2));
      await tester.pumpAndSettle();

      await tester.tap(row('C'));
      await tester.pump();
      await tester.tap(
        find.widgetWithText(OutlinedButton, es.suggestionReviewReject(1)),
      );
      await tester.pumpAndSettle();

      expect(sheet(), findsNothing);
      expect(await propertyOwners(), isEmpty);
      expect((await statuses())[ids[2]], SuggestionStatus.rejected);
      expect((await statuses())[ids[1]], SuggestionStatus.pending);
      expect(find.text(es.suggestionReviewRejected(1)), findsOneWidget);
      expect(find.text(es.suggestionReviewUndo), findsNothing);
      // Queda uno solo con la sugerencia: «1 elemento más».
      expect(offer(1), findsOneWidget);
    });

    testWidgets('cerrar la hoja sin decidir no cambia nada', (tester) async {
      final ids = await threeWithRoma();
      await pumpInbox(tester);
      await tester.tap(offer(2));
      await tester.pumpAndSettle();
      await tester.tap(row('B'));
      await tester.pump();

      // Arrastrar la hoja hacia abajo la cierra.
      await tester.drag(
        find.text(es.suggestionReviewHint),
        const Offset(0, 900),
      );
      await tester.pumpAndSettle();

      expect(sheet(), findsNothing);
      expect(await propertyOwners(), isEmpty);
      expect((await statuses()).values.toSet(), {SuggestionStatus.pending});
      expect(find.text('A'), findsOneWidget);
      expect(await stateOf(ids.first), ItemState.processed);
    });

    testWidgets('cuando ya no queda nadie más, la oferta desaparece', (
      tester,
    ) async {
      await threeWithRoma();
      await pumpInbox(tester);
      await tester.tap(offer(2));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, es.suggestionReviewAccept(2)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('más parecen'), findsNothing);
      expect(find.textContaining('más parece'), findsNothing);
    });
  });
}
