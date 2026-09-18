import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/inbox/presentation/screens/inbox_screen.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  var counter = 0;

  setUp(() async {
    harness = await LibraryHarness.create();
    counter = 0;
  });

  /// Guarda una fuente ya "procesada" —lista para triar— directo por el
  /// mismo repositorio que usa la app, para que el espejo (F3) la deje en
  /// `ItemState.processed`. No pasa por la cola de la app: los adaptadores
  /// de URL dejarían el elemento en `pending` a propósito, esperando un
  /// procesamiento que la cola de mentira del harness nunca hace.
  Future<String> seedProcessedSource({String title = 'Un elemento'}) async {
    final n = counter++;
    final now = DateTime(2026, 9, 18, 10);
    final item = KnowledgeItem(
      id: 'item-$n',
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
    );
    await harness.container.read(libraryRepositoryProvider).save(item);
    return item.id;
  }

  Future<void> pumpInbox(WidgetTester tester) async {
    await tester.pumpWidget(harness.wrap(const InboxScreen()));
    await tester.pumpAndSettle();
  }

  Future<String> seedSuggestion(
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
    final result = await harness.container
        .read(suggestionRepositoryProvider)
        .createPropertySuggestion(
          targetItemId: itemId,
          definitionId: definition.id,
          definitionName: category,
          value: value,
          isNewValue: true,
        );
    return result.getRight().toNullable()!.id;
  }

  testWidgets('sin nada pendiente, explica que no hay nada que triar', (
    tester,
  ) async {
    await pumpInbox(tester);

    expect(find.text(es.inboxEmptyTitle), findsOneWidget);
  });

  testWidgets('una fuente procesada aparece, con el contador correcto', (
    tester,
  ) async {
    await seedProcessedSource(title: 'Un artículo cualquiera');

    await pumpInbox(tester);

    expect(find.text('Un artículo cualquiera'), findsOneWidget);
    expect(find.text(es.inboxPendingCount(1)), findsOneWidget);
  });

  testWidgets('tocar Descartar la saca de la Bandeja', (tester) async {
    await seedProcessedSource(title: 'Algo para descartar');

    await pumpInbox(tester);
    await tester.tap(find.text(es.inboxActionDiscard));
    await tester.pumpAndSettle();

    expect(find.text('Algo para descartar'), findsNothing);
    expect(find.text(es.inboxEmptyTitle), findsOneWidget);
  });

  group('revisar sugerencias', () {
    testWidgets('sin sugerencias pendientes, no muestra el botón', (
      tester,
    ) async {
      await seedProcessedSource();

      await pumpInbox(tester);

      expect(find.text(es.inboxActionReviewSuggestions), findsNothing);
    });

    testWidgets(
      'con sugerencias pendientes, tocarlo transiciona a triaged y abre '
      'el diálogo',
      (tester) async {
        final itemId = await seedProcessedSource();
        await seedSuggestion(itemId);

        await pumpInbox(tester);
        expect(find.text(es.inboxActionReviewSuggestions), findsOneWidget);

        await tester.tap(find.text(es.inboxActionReviewSuggestions));
        await tester.pumpAndSettle();

        expect(find.text(es.suggestionsReviewDialogTitle), findsOneWidget);
        // Transicionó a triaged: la fuente ya no aparece en pending.
        expect(find.text(es.inboxEmptyTitle), findsOneWidget);
      },
    );

    testWidgets('aceptar una sugerencia la aplica de verdad', (tester) async {
      final itemId = await seedProcessedSource();
      await seedSuggestion(itemId);

      await pumpInbox(tester);
      await tester.tap(find.text(es.inboxActionReviewSuggestions));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.suggestionsApplySelected));
      await tester.pumpAndSettle();

      final reloaded =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .findById(itemId))
              .getRight()
              .toNullable()!;
      expect(reloaded.properties, hasLength(1));
      expect(reloaded.properties.single.value, 'Roma');
    });
  });
}
