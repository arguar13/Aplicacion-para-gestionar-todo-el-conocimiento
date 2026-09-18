import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';
import 'package:sinapsis/features/suggestions/presentation/widgets/suggestion_review_dialog.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// Un botón que abre `showSuggestionReviewDialog` — mismo esqueleto que un
/// widget host mínimo para probar una función pública que necesita
/// `BuildContext`+`SuggestionRepository` sin depender de la Bandeja
/// entera.
class _Host extends ConsumerWidget {
  const _Host({required this.suggestions});

  final List<Suggestion> suggestions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showSuggestionReviewDialog(
            context,
            repository: ref.read(suggestionRepositoryProvider),
            suggestions: suggestions,
          ),
          child: const Text('abrir'),
        ),
      ),
    );
  }
}

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  var counter = 0;

  setUp(() async {
    harness = await LibraryHarness.create();
    counter = 0;
  });

  Future<KnowledgeItem> seedItem() async {
    final n = counter++;
    final now = DateTime(2026, 9, 18, 10);
    final item = KnowledgeItem(
      id: 'item-$n',
      title: 'Un elemento',
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
    final result = await harness.container
        .read(libraryRepositoryProvider)
        .save(item);
    return result.getRight().toNullable()!;
  }

  Future<Suggestion> seedSuggestion(
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
    return result.getRight().toNullable()!;
  }

  Future<void> pumpHost(
    WidgetTester tester,
    List<Suggestion> suggestions,
  ) async {
    await tester.pumpWidget(harness.wrap(_Host(suggestions: suggestions)));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('aceptar una marcada la aplica de verdad', (tester) async {
    final item = await seedItem();
    final suggestion = await seedSuggestion(item.id);

    await pumpHost(tester, [suggestion]);
    await tester.tap(find.text(es.suggestionsApplySelected));
    await tester.pumpAndSettle();

    final row = await (harness.database.select(
      harness.database.suggestions,
    )..where((s) => s.id.equals(suggestion.id))).getSingle();
    expect(row.status, SuggestionStatus.accepted);

    final reloaded =
        (await harness.container
                .read(libraryRepositoryProvider)
                .findById(item.id))
            .getRight()
            .toNullable()!;
    expect(reloaded.properties, hasLength(1));
    expect(reloaded.properties.single.value, 'Roma');
  });

  testWidgets('dejar una desmarcada no la toca', (tester) async {
    final item = await seedItem();
    final suggestion = await seedSuggestion(item.id);

    await pumpHost(tester, [suggestion]);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text(es.suggestionsApplySelected));
    await tester.pumpAndSettle();

    final row = await (harness.database.select(
      harness.database.suggestions,
    )..where((s) => s.id.equals(suggestion.id))).getSingle();
    expect(row.status, SuggestionStatus.pending);
  });

  testWidgets('cancelar no llama a nada', (tester) async {
    final item = await seedItem();
    final suggestion = await seedSuggestion(item.id);

    await pumpHost(tester, [suggestion]);
    await tester.tap(find.text(es.commonCancel));
    await tester.pumpAndSettle();

    final row = await (harness.database.select(
      harness.database.suggestions,
    )..where((s) => s.id.equals(suggestion.id))).getSingle();
    expect(row.status, SuggestionStatus.pending);
  });
}
