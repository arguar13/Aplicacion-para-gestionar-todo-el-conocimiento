import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/create_hub/domain/create_kind.dart';
import 'package:sinapsis/features/notes/domain/services/derived_note_generator.dart';
import 'package:sinapsis/features/notes/domain/usecases/generate_derived_note_usecase.dart';
import 'package:sinapsis/features/notes/presentation/providers/derived_note_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../support/create_fixture.dart';
import '../../../support/library_harness.dart';

/// Devuelve exactamente el resultado que se le da y guarda con qué
/// [GenerateDerivedNoteParams] la llamaron —acá lo que importa es cómo
/// reacciona «Crear» (el menú, el aviso, el resultado, cómo va y cancelar),
/// no la orquestación del caso de uso, que ya se prueba sola en
/// `generate_derived_note_usecase_test.dart`—.
///
/// Con [parts], cuenta las partes como el de verdad —antes de cada una y al
/// final— y espera a [gate] antes de la última, para ver cómo va y cancelar.
class _FakeGenerateDerivedNoteUseCase implements GenerateDerivedNoteUseCase {
  _FakeGenerateDerivedNoteUseCase(this._result, {this.parts = 1, this.gate});

  final Either<Failure, DerivedNoteResult> Function(GenerateDerivedNoteParams)
  _result;
  final int parts;
  final Completer<void>? gate;
  GenerateDerivedNoteParams? paramsSeen;

  /// Si llegó a guardar: después del último aviso de cómo va.
  bool saved = false;

  @override
  Future<Either<Failure, DerivedNoteResult>> call(
    GenerateDerivedNoteParams params,
  ) async {
    paramsSeen = params;
    for (var i = 0; i < parts; i++) {
      params.onProgress?.call(i, parts);
      if (i == parts - 1) await gate?.future;
    }
    params.onProgress?.call(parts, parts);
    saved = true;
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

/// «Nota derivada», en «Crear» (F16, 12c; F45, paso 7b): el menú de tipos,
/// el aviso de modelo requerido, el resultado —creada o con error— de la
/// generación, cómo va por partes y «Cancelar».
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  Future<void> pumpButton(
    WidgetTester tester, {
    bool chatModelReady = false,
    _FakeGenerateDerivedNoteUseCase? useCase,
    String Function()? modelName,
  }) async {
    harness = await LibraryHarness.create(chatModelReady: chatModelReady);
    await tester.pumpWidget(
      harness.wrap(
        ProviderScope(
          overrides: [
            if (useCase != null)
              generateDerivedNoteUseCaseProvider.overrideWithValue(useCase),
            if (modelName != null)
              languageModelNameProvider.overrideWithValue(modelName),
          ],
          child: createScreen(CreateTarget.note(_fixtureNote('a', 'Fuente'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sin el modelo descargado, avisa y ofrece descargarlo', (
    tester,
  ) async {
    await pumpButton(tester);

    await tapCreate(tester, CreateKind.derivedNote);

    expect(find.text(es.derivedNoteModelRequired), findsOneWidget);
    expect(find.text(es.derivedNoteDownloadAction), findsOneWidget);
  });

  testWidgets('con el modelo listo, elegir un tipo genera y avisa', (
    tester,
  ) async {
    final useCase = _FakeGenerateDerivedNoteUseCase(
      (params) =>
          right(DerivedNoteResult(note: _fixtureNote('nueva', params.title))),
    );
    await pumpButton(tester, chatModelReady: true, useCase: useCase);

    await tapCreate(tester, CreateKind.derivedNote);
    await tester.tap(find.text(es.derivedNoteTypeOutline));
    await tester.pumpAndSettle();

    final expectedTitle = es.derivedNoteTitleOutline('Fuente');
    expect(find.text(es.derivedNoteCreated(expectedTitle)), findsOneWidget);
    expect(find.text(es.derivedNoteViewAction), findsOneWidget);

    final params = useCase.paramsSeen!;
    expect(params.type, DerivedNoteType.outline);
    expect(params.itemId, 'a');
    expect(params.title, expectedTitle);
  });

  testWidgets('un tipo distinto pide el título y el tipo correctos', (
    tester,
  ) async {
    final useCase = _FakeGenerateDerivedNoteUseCase(
      (params) =>
          right(DerivedNoteResult(note: _fixtureNote('nueva', params.title))),
    );
    await pumpButton(tester, chatModelReady: true, useCase: useCase);

    await tapCreate(tester, CreateKind.derivedNote);
    await tester.tap(find.text(es.derivedNoteTypeTimeline));
    await tester.pumpAndSettle();

    final params = useCase.paramsSeen!;
    expect(params.type, DerivedNoteType.timeline);
    expect(params.itemId, 'a');
    expect(params.title, es.derivedNoteTitleTimeline('Fuente'));
  });

  testWidgets('anota el modelo que escribe de verdad, también el de la nube '
      '(F32)', (tester) async {
    final useCase = _FakeGenerateDerivedNoteUseCase(
      (params) =>
          right(DerivedNoteResult(note: _fixtureNote('nueva', params.title))),
    );
    await pumpButton(
      tester,
      chatModelReady: true,
      useCase: useCase,
      modelName: () => 'gemini-3.8-flash',
    );

    await tapCreate(tester, CreateKind.derivedNote);
    await tester.tap(find.text(es.derivedNoteTypeOutline));
    await tester.pumpAndSettle();

    expect(useCase.paramsSeen!.model, 'gemini-3.8-flash');
  });

  testWidgets('si el caso de uso falla, avisa el error', (tester) async {
    final useCase = _FakeGenerateDerivedNoteUseCase(
      (_) => left(
        const Failure.validation(message: 'nada que anclar en la prueba'),
      ),
    );
    await pumpButton(tester, chatModelReady: true, useCase: useCase);

    await tapCreate(tester, CreateKind.derivedNote);
    await tester.tap(find.text(es.derivedNoteTypeOutline));
    await tester.pumpAndSettle();

    expect(find.text(es.globalErrorValidation), findsOneWidget);
    expect(find.text(es.derivedNoteViewAction), findsNothing);
  });

  group('mientras escribe (F45, paso 7b)', () {
    testWidgets('la fila dice qué parte lee, con su barra y «Cancelar», y el '
        '✨ lleva el anillo que se llena', (tester) async {
      final gate = Completer<void>();
      final useCase = _FakeGenerateDerivedNoteUseCase(
        (params) =>
            right(DerivedNoteResult(note: _fixtureNote('nueva', params.title))),
        parts: 2,
        gate: gate,
      );
      await pumpButton(tester, chatModelReady: true, useCase: useCase);

      await tapCreate(tester, CreateKind.derivedNote);
      await tester.tap(find.text(es.derivedNoteTypeOutline));
      await tester.pump();

      final ring = tester.widget<CircularProgressIndicator>(
        find.byKey(const Key('create-button-ring')),
      );
      expect(ring.value, 0.5);
      expect(find.byTooltip(es.f45S7bCreateBusy), findsOneWidget);

      await tester.tap(find.byKey(const Key('create-button')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('create-derivedNote')),
          matching: find.text(es.flashcardsReadingPart(2, 2)),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('create-derivedNote-cancel')),
        findsOneWidget,
      );

      gate.complete();
      await tester.pumpAndSettle();
      expect(useCase.saved, isTrue);
      expect(find.byKey(const Key('create-button-ring')), findsNothing);
    });

    testWidgets('«Cancelar» corta antes de guardar: no queda nota ni aviso, '
        'y la fila vuelve a ofrecerla', (tester) async {
      final gate = Completer<void>();
      final useCase = _FakeGenerateDerivedNoteUseCase(
        (params) =>
            right(DerivedNoteResult(note: _fixtureNote('nueva', params.title))),
        parts: 2,
        gate: gate,
      );
      await pumpButton(tester, chatModelReady: true, useCase: useCase);

      await tapCreate(tester, CreateKind.derivedNote);
      await tester.tap(find.text(es.derivedNoteTypeOutline));
      await tester.pump();
      await tester.tap(find.byKey(const Key('create-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('create-derivedNote-cancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('create-derivedNote-cancel')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('create-derivedNote')),
          matching: find.text(es.f45S7bDerivedNoteHint),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('create-button-ring')), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
      expect(useCase.saved, isFalse);
      final title = es.derivedNoteTitleOutline('Fuente');
      expect(find.text(es.derivedNoteCreated(title)), findsNothing);
    });
  });
}
