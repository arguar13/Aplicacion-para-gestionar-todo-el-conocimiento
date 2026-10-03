import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' show Either, right;
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/core/error/failures.dart';
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
  const _Host({required this.suggestions, required this.onDone});

  final List<Suggestion> suggestions;

  /// Cómo terminó la revisión: lo que la Bandeja usa para decidir si tría
  /// (F28).
  final ValueChanged<Either<Failure, int>?> onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async => onDone(
            await showSuggestionReviewDialog(
              context,
              repository: ref.read(suggestionRepositoryProvider),
              suggestions: suggestions,
            ),
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

  /// Lo que devolvió la última revisión; `done` dice si ya terminó.
  var done = false;
  Either<Failure, int>? outcome;

  Future<void> pumpHost(
    WidgetTester tester,
    List<Suggestion> suggestions,
  ) async {
    done = false;
    outcome = null;
    await tester.pumpWidget(
      harness.wrap(
        _Host(
          suggestions: suggestions,
          onDone: (result) {
            done = true;
            outcome = result;
          },
        ),
      ),
    );
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
    expect(outcome, right<Failure, int>(1));

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
    // Confirmar sin ninguna tildada también es haber revisado.
    expect(outcome, right<Failure, int>(0));
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
    expect(done, isTrue);
    expect(outcome, isNull);
  });

  testWidgets('una que no se puede aplicar devuelve el fallo, y las demás se '
      'aplican igual', (tester) async {
    final item = await seedItem();
    final good = await seedSuggestion(item.id);
    final gone = (await seedSuggestion(
      item.id,
      category: 'Época',
      value: 'Siglo I',
    )).copyWith(id: 'ya-no-existe');

    await pumpHost(tester, [gone, good]);
    await tester.tap(find.text(es.suggestionsApplySelected));
    await tester.pumpAndSettle();

    expect(outcome!.isLeft(), isTrue);
    final row = await (harness.database.select(
      harness.database.suggestions,
    )..where((s) => s.id.equals(good.id))).getSingle();
    expect(row.status, SuggestionStatus.accepted);
  });
}
