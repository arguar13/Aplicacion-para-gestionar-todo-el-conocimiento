import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';
import 'package:sinapsis/features/suggestions/presentation/widgets/review_suggestions_action.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
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

  Future<String> seedItem() async {
    final n = counter++;
    final now = DateTime(2026, 9, 19, 10);
    final item = KnowledgeItem(
      id: 'item-$n',
      title: 'Elemento $n',
      source: Source(id: 'src-$n', kind: SourceKind.webPage, capturedAt: now),
      processingState: ProcessingState.ready,
      createdAt: now,
      updatedAt: now,
    );
    await harness.container.read(libraryRepositoryProvider).save(item);
    return item.id;
  }

  Future<void> suggest(String itemId, String value) async {
    final definition =
        (await harness.container
                .read(organizeRepositoryProvider)
                .getOrCreatePropertyDefinition('Región'))
            .getRight()
            .toNullable()!;
    await harness.container
        .read(suggestionRepositoryProvider)
        .createPropertySuggestion(
          targetItemId: itemId,
          definitionId: definition.id,
          definitionName: 'Región',
          value: value,
          isNewValue: true,
        );
  }

  Future<void> pumpAction(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp.router(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => Scaffold(
                  appBar: AppBar(actions: const [ReviewSuggestionsAction()]),
                ),
              ),
              GoRoute(
                path: RoutePaths.suggestionReview,
                builder: (_, _) => const Scaffold(body: Text('la revisión')),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sin sugerencias pendientes no ocupa lugar', (tester) async {
    await pumpAction(tester);

    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('con sugerencias muestra cuántas hay, sumando todos los '
      'grupos', (tester) async {
    await suggest(await seedItem(), 'Roma');
    await suggest(await seedItem(), 'Roma');
    await suggest(await seedItem(), 'Cartago');

    await pumpAction(tester);

    expect(find.byTooltip(es.suggestionReviewOpenTooltip(3)), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('tocarlo abre la revisión en lote', (tester) async {
    await suggest(await seedItem(), 'Roma');
    await pumpAction(tester);

    await tester.tap(find.byTooltip(es.suggestionReviewOpenTooltip(1)));
    await tester.pumpAndSettle();

    expect(find.text('la revisión'), findsOneWidget);
  });
}
