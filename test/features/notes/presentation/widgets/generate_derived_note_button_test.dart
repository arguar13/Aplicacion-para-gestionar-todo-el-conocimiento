import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/notes/domain/services/derived_note_generator.dart';
import 'package:sinapsis/features/notes/domain/usecases/generate_derived_note_usecase.dart';
import 'package:sinapsis/features/notes/presentation/providers/derived_note_providers.dart';
import 'package:sinapsis/features/notes/presentation/widgets/generate_derived_note_button.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// Devuelve exactamente el resultado que se le da y guarda con qué
/// [GenerateDerivedNoteParams] la llamaron —acá lo que importa es cómo
/// reacciona el BOTÓN (el menú, el aviso, el resultado), no la orquestación
/// del caso de uso, que ya se prueba sola en
/// `generate_derived_note_usecase_test.dart`—.
class _FakeGenerateDerivedNoteUseCase implements GenerateDerivedNoteUseCase {
  _FakeGenerateDerivedNoteUseCase(this._result);

  final Either<Failure, KnowledgeItem> Function(GenerateDerivedNoteParams)
  _result;
  GenerateDerivedNoteParams? paramsSeen;

  @override
  Future<Either<Failure, KnowledgeItem>> call(
    GenerateDerivedNoteParams params,
  ) async {
    paramsSeen = params;
    return _result(params);
  }
}

KnowledgeItem _fixtureNote(String id, String title) => KnowledgeItem(
  id: id,
  title: title,
  source: Source(
    id: 'src-$id',
    kind: SourceKind.manualNote,
    capturedAt: DateTime(2026, 9, 24),
  ),
  processingState: ProcessingState.ready,
  createdAt: DateTime(2026, 9, 24),
  updatedAt: DateTime(2026, 9, 24),
);

/// El botón "Generar derivado" (F16, 12c): el menú de tipos, el aviso de
/// modelo requerido, y el resultado —creada o con error— de la
/// generación.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  Future<void> pumpButton(
    WidgetTester tester, {
    bool chatModelReady = false,
    _FakeGenerateDerivedNoteUseCase? useCase,
    String? itemId,
    String? notebookId,
  }) async {
    harness = await LibraryHarness.create(chatModelReady: chatModelReady);
    await tester.pumpWidget(
      harness.wrap(
        ProviderScope(
          overrides: [
            if (useCase != null)
              generateDerivedNoteUseCaseProvider.overrideWithValue(useCase),
          ],
          child: Scaffold(
            body: GenerateDerivedNoteButton(
              sourceTitle: 'Fuente',
              itemId: itemId,
              notebookId: notebookId,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sin el modelo descargado, avisa y ofrece descargarlo', (
    tester,
  ) async {
    await pumpButton(tester, itemId: 'a');

    await tester.tap(find.byTooltip(es.derivedNoteGenerateTooltip));
    await tester.pumpAndSettle();

    expect(find.text(es.derivedNoteModelRequired), findsOneWidget);
    expect(find.text(es.derivedNoteDownloadAction), findsOneWidget);
  });

  testWidgets('con el modelo listo, elegir un tipo genera y avisa', (
    tester,
  ) async {
    final useCase = _FakeGenerateDerivedNoteUseCase(
      (params) => right(_fixtureNote('nueva', params.title)),
    );
    await pumpButton(
      tester,
      chatModelReady: true,
      useCase: useCase,
      itemId: 'a',
    );

    await tester.tap(find.byTooltip(es.derivedNoteGenerateTooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.text(es.derivedNoteTypeOutline));
    await tester.pumpAndSettle();

    final expectedTitle = es.derivedNoteTitleOutline('Fuente');
    expect(find.text(es.derivedNoteCreated(expectedTitle)), findsOneWidget);
    expect(find.text(es.derivedNoteViewAction), findsOneWidget);

    final params = useCase.paramsSeen!;
    expect(params.type, DerivedNoteType.outline);
    expect(params.itemId, 'a');
    expect(params.notebookId, isNull);
    expect(params.title, expectedTitle);
  });

  testWidgets('un tipo distinto pide el título y el tipo correctos', (
    tester,
  ) async {
    final useCase = _FakeGenerateDerivedNoteUseCase(
      (params) => right(_fixtureNote('nueva', params.title)),
    );
    await pumpButton(
      tester,
      chatModelReady: true,
      useCase: useCase,
      notebookId: 'nb-1',
    );

    await tester.tap(find.byTooltip(es.derivedNoteGenerateTooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.text(es.derivedNoteTypeTimeline));
    await tester.pumpAndSettle();

    final params = useCase.paramsSeen!;
    expect(params.type, DerivedNoteType.timeline);
    expect(params.notebookId, 'nb-1');
    expect(params.itemId, isNull);
    expect(params.title, es.derivedNoteTitleTimeline('Fuente'));
  });

  testWidgets('si el caso de uso falla, avisa el error', (tester) async {
    final useCase = _FakeGenerateDerivedNoteUseCase(
      (_) => left(
        const Failure.validation(message: 'nada que anclar en la prueba'),
      ),
    );
    await pumpButton(
      tester,
      chatModelReady: true,
      useCase: useCase,
      itemId: 'a',
    );

    await tester.tap(find.byTooltip(es.derivedNoteGenerateTooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.text(es.derivedNoteTypeOutline));
    await tester.pumpAndSettle();

    expect(find.text(es.globalErrorValidation), findsOneWidget);
    expect(find.text(es.derivedNoteViewAction), findsNothing);
  });
}
