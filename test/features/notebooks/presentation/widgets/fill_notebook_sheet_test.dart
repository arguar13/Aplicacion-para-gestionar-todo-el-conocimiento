import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_queue_providers.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/features/notebooks/presentation/screens/notebook_detail_screen.dart';
import 'package:sinapsis/features/notes/domain/services/derived_note_generator.dart';
import 'package:sinapsis/features/notes/domain/usecases/generate_derived_note_usecase.dart';
import 'package:sinapsis/features/notes/presentation/providers/derived_note_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/fake_ai_organize_queue.dart';
import '../../../../support/library_harness.dart';

/// Devuelve el resultado que se le da y guarda con qué lo llamaron: acá
/// importa la hoja, no la orquestación del caso de uso.
class _FakeGenerateDerivedNoteUseCase implements GenerateDerivedNoteUseCase {
  _FakeGenerateDerivedNoteUseCase({this.failure, this.inNotebook = true});

  final Failure? failure;
  final bool inNotebook;
  final calls = <GenerateDerivedNoteParams>[];

  @override
  Future<Either<Failure, DerivedNoteResult>> call(
    GenerateDerivedNoteParams params,
  ) async {
    calls.add(params);
    params.onProgress?.call(0, 1);
    params.onProgress?.call(1, 1);
    final failure = this.failure;
    if (failure != null) return left(failure);
    return right(
      DerivedNoteResult(
        note: KnowledgeItem(
          id: 'guia',
          title: params.title,
          source: Source(
            id: 'src-guia',
            kind: SourceKind.manualNote,
            capturedAt: DateTime(2026, 10, 8),
          ),
          processingState: ProcessingState.ready,
          createdAt: DateTime(2026, 10, 8),
          updatedAt: DateTime(2026, 10, 8),
        ),
        inNotebook: inNotebook,
      ),
    );
  }
}

/// «Llenar» desde el detalle de un cuaderno (F30).
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late FakeAiOrganizeQueue queue;
  late _FakeGenerateDerivedNoteUseCase useCase;

  Future<String> seedNotebook() async {
    await harness.capture('Roma antigua');
    await harness.capture('El Senado');
    final ids =
        (await harness.container
                .read(libraryRepositoryProvider)
                .matchingIds(const LibraryQuery()))
            .getRight()
            .toNullable()!;
    final repository = harness.container.read(notebookRepositoryProvider);
    final notebook = await repository.create(
      name: 'Roma',
      mode: NotebookMode.manual,
    );
    await repository.addItems(notebookId: notebook.id, itemIds: ids);
    return notebook.id;
  }

  Future<void> pumpDetail(
    WidgetTester tester, {
    required String notebookId,
  }) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: RoutePaths.notebooks,
          builder: (_, _) => NotebookDetailScreen(notebookId: notebookId),
        ),
        GoRoute(
          path: RoutePaths.itemDetailPattern,
          builder: (_, state) =>
              Scaffold(body: Text('detalle de ${state.pathParameters['id']}')),
        ),
      ],
      initialLocation: RoutePaths.notebooks,
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp.router(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> setUpHarness({
    bool chatModelReady = true,
    _FakeGenerateDerivedNoteUseCase? generate,
  }) async {
    queue = FakeAiOrganizeQueue();
    useCase = generate ?? _FakeGenerateDerivedNoteUseCase();
    harness = await LibraryHarness.create(
      chatModelReady: chatModelReady,
      extraOverrides: [
        aiOrganizeQueueProvider.overrideWithValue(queue),
        generateDerivedNoteUseCaseProvider.overrideWithValue(useCase),
      ],
    );
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('fill-notebook')));
    await tester.pumpAndSettle();
  }

  testWidgets('pide las tarjetas y la nota, y la nota queda en el cuaderno: '
      'se ve qué quedó hecho', (tester) async {
    await setUpHarness();
    final notebookId = await seedNotebook();
    await pumpDetail(tester, notebookId: notebookId);

    await openSheet(tester);
    expect(find.text(es.fillNotebookTitle), findsOneWidget);
    expect(find.textContaining(es.reviewAiCoverage(2)), findsOneWidget);

    await tester.tap(find.byKey(const Key('fill-notebook-start')));
    await tester.pumpAndSettle();

    expect(queue.flashcardRequests, hasLength(1));
    expect(queue.flashcardRequests.single, hasLength(2));
    expect(useCase.calls.single.notebookId, notebookId);
    expect(useCase.calls.single.title, es.derivedNoteTitleStudyGuide('Roma'));
    expect(find.text(es.fillNotebookCardsQueued(2)), findsOneWidget);
    expect(
      find.text(
        es.fillNotebookGuideDone(es.derivedNoteTitleStudyGuide('Roma')),
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const Key('fill-notebook-view-note')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fill-notebook-view-note')));
    await tester.pumpAndSettle();
    expect(find.text('detalle de guia'), findsOneWidget);
  });

  testWidgets('se puede elegir solo la nota, y de otro tipo', (tester) async {
    await setUpHarness();
    final notebookId = await seedNotebook();
    await pumpDetail(tester, notebookId: notebookId);

    await openSheet(tester);
    await tester.tap(find.byKey(const Key('fill-notebook-cards')));
    await tester.tap(
      find.byKey(Key('fill-notebook-type-${DerivedNoteType.timeline.name}')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('fill-notebook-start')));
    await tester.pumpAndSettle();

    expect(queue.flashcardRequests, isEmpty);
    expect(useCase.calls.single.type, DerivedNoteType.timeline);
    expect(
      find.text(es.fillNotebookGuideDone(es.derivedNoteTitleTimeline('Roma'))),
      findsOneWidget,
    );
  });

  testWidgets('sin el modelo de lenguaje, ofrece bajarlo y no empieza', (
    tester,
  ) async {
    await setUpHarness(chatModelReady: false);
    final notebookId = await seedNotebook();
    await pumpDetail(tester, notebookId: notebookId);

    await openSheet(tester);

    expect(find.text(es.derivedNoteModelRequired), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('fill-notebook-start')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('si la nota queda fuera del cuaderno, lo dice', (tester) async {
    await setUpHarness(
      generate: _FakeGenerateDerivedNoteUseCase(inNotebook: false),
    );
    final notebookId = await seedNotebook();
    await pumpDetail(tester, notebookId: notebookId);

    await openSheet(tester);
    await tester.tap(find.byKey(const Key('fill-notebook-start')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        es.fillNotebookGuideElsewhere(es.derivedNoteTitleStudyGuide('Roma')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('si la nota no se pudo armar, dice por qué y las tarjetas ya '
      'quedaron pedidas', (tester) async {
    await setUpHarness(
      generate: _FakeGenerateDerivedNoteUseCase(
        failure: const Failure.validation(message: 'Nada que citar.'),
      ),
    );
    final notebookId = await seedNotebook();
    await pumpDetail(tester, notebookId: notebookId);

    await openSheet(tester);
    await tester.tap(find.byKey(const Key('fill-notebook-start')));
    await tester.pumpAndSettle();

    expect(find.text(es.fillNotebookGuideNothingToCite), findsOneWidget);
    expect(find.text(es.fillNotebookCardsQueued(2)), findsOneWidget);
    expect(queue.flashcardRequests, hasLength(1));
    expect(find.byKey(const Key('fill-notebook-view-note')), findsNothing);
  });
}
