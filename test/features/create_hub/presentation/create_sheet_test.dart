import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_settings_notifier.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/create_hub/domain/create_kind.dart';
import 'package:sinapsis/features/create_hub/presentation/create_runs.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcard_generator.dart';
import 'package:sinapsis/features/organize/presentation/widgets/pick_item_dialog.dart';
import 'package:sinapsis/features/processed/domain/entities/extract_note_target.dart';
import 'package:sinapsis/features/processed/domain/entities/process_outcome.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_document.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../support/create_fixture.dart';
import '../../../support/fake_extract_note.dart';
import '../../../support/library_harness.dart';

final _now = DateTime(2026, 10, 30, 10);

/// Un elemento con [text] como su texto principal.
KnowledgeItem _item(String id, {String text = 'Nació en 1809.'}) =>
    KnowledgeItem(
      id: id,
      title: 'Darwin',
      source: Source(id: id, kind: SourceKind.manualNote, capturedAt: _now),
      processingState: ProcessingState.ready,
      createdAt: _now,
      updatedAt: _now,
      renditions: [
        Rendition.text(
          id: '$id-texto',
          itemId: id,
          kind: RenditionKind.plainText,
          content: text,
          isPrimary: true,
          createdAt: _now,
        ),
      ],
    );

/// Un modelo de tarjetas que espera, en cada parte, a que la prueba la deje
/// seguir: para ver cómo va y cancelar en el medio.
class _GatedGenerator implements FlashcardGenerator {
  final contents = <String>[];
  final gates = <Completer<void>>[];

  @override
  Future<List<FlashcardDraft>> generate({
    required String content,
    int count = 5,
  }) async {
    contents.add(content);
    final gate = Completer<void>();
    gates.add(gate);
    await gate.future;
    return [
      FlashcardDraft(
        front: '¿Qué dice la parte ${contents.length}?',
        back: 'Algo.',
        quote: content.substring(0, 10),
      ),
    ];
  }
}

/// «Crear» (F45, paso 7b, mejora 14, decisión G): lo que se crea de un
/// documento, en un solo lugar —con IA y a mano—, con cómo va cada cosa,
/// «Cancelar», el anillo del ✨ y el porqué de lo que no se puede.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  Future<void> pump(
    WidgetTester tester,
    CreateTarget target, {
    LibraryHarness? withHarness,
    ThemeData? theme,
    Size size = const Size(800, 1600),
    double textScale = 1,
  }) async {
    harness = withHarness ?? await LibraryHarness.create(chatModelReady: true);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness.wrap(
        MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: Theme(
            data: theme ?? AppTheme.lightTheme,
            child: createScreen(target),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('create-button')));
    await tester.pumpAndSettle();
  }

  String detailOf(WidgetTester tester, CreateKind kind) =>
      tester.widget<Text>(find.byKey(Key('create-${kind.name}-detail'))).data!;

  group('qué ofrece', () {
    testWidgets('en un documento procesado: con IA, organizar, tarjetas, '
        'cuestionario, nota derivada y fechas; a mano, tarjeta, nota y '
        'vínculo, en ese orden y cada una con lo que hace', (tester) async {
      await pump(tester, processedTargetOf(_item('p')));
      await openSheet(tester);

      final tops = [
        for (final kind in CreateKind.values)
          tester.getTopLeft(find.byKey(Key('create-${kind.name}'))).dy,
      ];
      expect(tops, orderedEquals([...tops]..sort()));
      expect(find.text(es.f45S7bByHand), findsOneWidget);
      expect(find.textContaining(es.f45S7bWithAi('')), findsOneWidget);
      for (final (kind, hint) in [
        (CreateKind.organize, es.f45S7bOrganizeHint),
        (CreateKind.flashcards, es.f45S7bFlashcardsHint),
        (CreateKind.quiz, es.f45S7bQuizHint),
        (CreateKind.derivedNote, es.f45S7bDerivedNoteHint),
        (CreateKind.dates, es.f45S7bDatesHint),
        (CreateKind.card, es.f45S7bCardHint),
        (CreateKind.note, es.f45S7bNoteHint),
        (CreateKind.link, es.f45S7bLinkHint),
      ]) {
        expect(detailOf(tester, kind), hint, reason: kind.name);
      }
      // El lector de pantalla lee cada fila como un botón, con lo que hace.
      expect(
        tester.getSemantics(find.byKey(const Key('create-quiz'))),
        matchesSemantics(
          label: '${es.f45S7bQuiz}. ${es.f45S7bQuizHint}',
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          hasTapAction: true,
        ),
      );
    });

    testWidgets('en una nota de la Biblioteca, sin «Nota»: lo que se escribe '
        'va en la nota misma', (tester) async {
      await pump(tester, CreateTarget.note(_item('n')));
      await openSheet(tester);

      expect(find.byKey(const Key('create-note')), findsNothing);
      for (final kind in CreateKind.values.where((k) => k != CreateKind.note)) {
        expect(find.byKey(Key('create-${kind.name}')), findsOneWidget);
      }
    });

    testWidgets('lo que no se puede ahora se ve apagado, con el porqué, y '
        'tocarlo no hace nada', (tester) async {
      await pump(
        tester,
        processedTargetOf(
          _item('p'),
          partCounts: const {},
          source: const ProcessedSourceLink(
            itemId: 'fuente',
            title: 'Fuente',
            inTrash: true,
          ),
        ),
      );
      await openSheet(tester);

      expect(detailOf(tester, CreateKind.dates), es.f45S7bBlockNoText);
      expect(detailOf(tester, CreateKind.note), es.f45S7bBlockSourceInTrash);
      await tester.tap(find.byKey(const Key('create-note')));
      await tester.pumpAndSettle();
      // La hoja sigue abierta y no se abrió el diálogo de la nota.
      expect(find.byKey(const Key('create-sheet')), findsOneWidget);
      expect(find.byKey(const Key('triage-note-field')), findsNothing);
    });

    test('sin su fuente, la nota a mano no se puede: se arma con ella', () {
      final target = processedTargetOf(_item('p'), source: null);
      expect(target.blockOf(CreateKind.note), CreateBlock.sourceGone);
      expect(target.sourceItemId, isNull);
      expect(processedTargetOf(_item('p')).blockOf(CreateKind.note), isNull);
    });
  });

  group('mientras trabaja', () {
    testWidgets('las tarjetas: la fila dice qué parte lee, el ✨ lleva el '
        'anillo que se llena, y «Cancelar» corta antes de la próxima parte '
        'sin abrir la revisión', (tester) async {
      final model = _GatedGenerator();
      final ready = await LibraryHarness.create(
        chatModelReady: true,
        extraOverrides: [flashcardGeneratorProvider.overrideWithValue(model)],
      );
      // Un libro: varias partes.
      final book = [
        for (var i = 0; i < 3000; i++) 'La idea número $i del libro es esta.',
      ].join(' ');
      await pump(
        tester,
        CreateTarget.note(_item('n', text: book)),
        withHarness: ready,
      );
      await openSheet(tester);
      await tester.tap(find.byKey(const Key('create-flashcards')));
      await tester.pump();
      await tester.pump();

      expect(model.gates, hasLength(1));
      final ring = tester.widget<CircularProgressIndicator>(
        find.byKey(const Key('create-button-ring')),
      );
      expect(ring.value, 0);

      await openSheet(tester);
      final detail = detailOf(tester, CreateKind.flashcards);
      expect(detail, matches(RegExp(r'^Leyendo la parte 1 de \d+…$')));
      final cancel = find.byKey(const Key('create-flashcards-cancel'));
      await tester.ensureVisible(cancel);
      await tester.pumpAndSettle();
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('create-button-ring')), findsNothing);
      expect(detailOf(tester, CreateKind.flashcards), es.f45S7bFlashcardsHint);

      // La parte que estaba leyendo termina sola; no se lee otra.
      model.gates.single.complete();
      await tester.pumpAndSettle();
      expect(model.contents, hasLength(1));
      expect(find.text(es.flashcardsReviewTitle), findsNothing);
    });

    testWidgets('lo que la cola de fondo hace con este documento se ve en su '
        'fila, con «Ver», y en el anillo; lo de otro, no', (tester) async {
      await pump(tester, processedTargetOf(_item('p')));
      harness.container
          .read(aiOrganizeStatusProvider.notifier)
          .state = const AiOrganizeWorking(
        itemId: 'otro',
        itemTitle: 'Otro',
        pending: 0,
        source: AiWorkSource.requested,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('create-button-ring')), findsNothing);

      harness.container
          .read(aiOrganizeStatusProvider.notifier)
          .state = const AiOrganizeWorking(
        itemId: 'p',
        itemTitle: 'Darwin',
        pending: 0,
        source: AiWorkSource.datesRequest,
      );
      await tester.pump();
      expect(find.byKey(const Key('create-button-ring')), findsOneWidget);
      expect(find.byTooltip(es.f45S7bCreateBusy), findsOneWidget);

      await tester.tap(find.byKey(const Key('create-button')));
      // Un cuadro para que empiece a subir la hoja y otro para que llegue.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(detailOf(tester, CreateKind.dates), es.f45S7bFindingDates);
      expect(find.byKey(const Key('create-dates-see')), findsOneWidget);
      expect(find.byKey(const Key('create-dates-cancel')), findsNothing);
      expect(detailOf(tester, CreateKind.organize), es.f45S7bOrganizeHint);
    });

    test('la cola organizando cuenta como «Organizar»; sus tarjetas de '
        'Repasar, no: no se pidieron desde acá', () {
      for (final (source, kind) in [
        (AiWorkSource.requested, CreateKind.organize),
        (AiWorkSource.fresh, CreateKind.organize),
        (AiWorkSource.changedNote, CreateKind.organize),
        (AiWorkSource.existingLibrary, CreateKind.organize),
        (AiWorkSource.datesRequest, CreateKind.dates),
        (AiWorkSource.flashcardsRequest, null),
      ]) {
        expect(
          queuedCreateOf(
            AiOrganizeWorking(
              itemId: 'p',
              itemTitle: 'Darwin',
              pending: 0,
              source: source,
            ),
            'p',
          ),
          kind,
          reason: source.name,
        );
      }
      expect(queuedCreateOf(const AiOrganizeIdle(), 'p'), isNull);
    });
  });

  group('a mano', () {
    testWidgets('«Nota» la escribe y la manda a las notas del documento, con '
        '«Deshacer»', (tester) async {
      const undo = ProcessUndo(
        documentId: 'p',
        previousStatus: ProcessedDocumentStatus.active,
        previous: {},
      );
      final notes = FakeExtractNote(
        const ExtractedToProcessed(
          documentId: 'p',
          created: false,
          unchanged: false,
          undo: undo,
        ),
      );
      final ready = await LibraryHarness.create(
        extraOverrides: [
          extractNoteToProcessedProvider.overrideWithValue(notes),
        ],
      );
      await pump(tester, processedTargetOf(_item('p')), withHarness: ready);

      await tapCreate(tester, CreateKind.note);
      await tester.enterText(
        find.byKey(const Key('triage-note-field')),
        'Mi idea.',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('triage-note-add')));
      await tester.pumpAndSettle();

      expect(notes.written, [(documentId: 'p', text: 'Mi idea.')]);
      expect(find.text(es.f45S7bNoteAdded), findsOneWidget);
      await tester.tap(find.text(es.inboxUndo));
      await tester.pumpAndSettle();
      expect(notes.undone, [undo]);
    });

    testWidgets('«Vínculo» abre la elección del otro documento', (
      tester,
    ) async {
      await pump(tester, processedTargetOf(_item('p')));

      await tapCreate(tester, CreateKind.link);

      expect(find.byType(PickItemDialog), findsOneWidget);
    });
  });

  group('en un teléfono', () {
    for (final (name, theme) in [
      ('claro', AppTheme.lightTheme),
      ('oscuro', AppTheme.darkTheme),
    ]) {
      testWidgets('a 360 dp con la letra al doble, tema $name: la hoja entra '
          'sin desbordarse y se desplaza hasta la última fila', (tester) async {
        await pump(
          tester,
          processedTargetOf(_item('p')),
          theme: theme,
          size: const Size(360, 800),
          textScale: 2,
        );
        await openSheet(tester);
        expect(tester.takeException(), isNull);

        final last = find.byKey(const Key('create-link'));
        await tester.scrollUntilVisible(
          last,
          200,
          scrollable: find.descendant(
            of: find.byKey(const Key('create-sheet')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.getBottomLeft(last).dy, lessThanOrEqualTo(800));
      });
    }
  });
}
