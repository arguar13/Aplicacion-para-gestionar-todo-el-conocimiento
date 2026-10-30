import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/app_snack_bar.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/services/ai_rejection_fingerprint.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/features/ai_models/presentation/language_model_missing.dart';
import 'package:sinapsis/features/ai_organize/domain/services/flashcard_target.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_organize_now.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/create_hub/domain/create_kind.dart';
import 'package:sinapsis/features/create_hub/presentation/create_runs.dart';
import 'package:sinapsis/features/flashcards/domain/entities/card_form.dart';
import 'package:sinapsis/features/flashcards/domain/services/cloze_generator.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcards_by_parts.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/card_form_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/quiz_review_screen.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/quiz_session_screen.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/card_form_cloze_review.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/card_form_dialog.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/flashcard_draft_review_dialog.dart';
import 'package:sinapsis/features/notes/domain/services/derived_note_generator.dart';
import 'package:sinapsis/features/notes/domain/usecases/generate_derived_note_usecase.dart';
import 'package:sinapsis/features/notes/presentation/providers/derived_note_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/relations_section.dart';
import 'package:sinapsis/features/processed/domain/entities/extract_note_target.dart';
import 'package:sinapsis/features/processed/domain/services/processed_card_text.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/widgets/write_note_dialog.dart';
import 'package:sinapsis/features/reading/domain/extractable_text.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cuántas tarjetas propone la IA como mínimo, aunque el texto sea corto: la
/// persona las revisa antes de guardar, y elegir entre algunas más cuesta
/// poco.
const kManualFlashcardsWanted = 5;

/// Hace [kind] sobre [target], elegido en «Crear» (F45, paso 7b, mejora 14).
///
/// Lo de la IA de esta pantalla —las tarjetas, el cuestionario y la nota
/// derivada— va por [createRunsProvider], que lo muestra trabajando en la hoja
/// y en el anillo del ✨, con «Cancelar». Organizar y buscar fechas los hace la
/// cola de la IA de fondo, que sigue aunque se cierre la pantalla, y el aviso
/// lo dice con «Ver». Lo de a mano abre su diálogo.
///
/// [context] es el de la pantalla, no el de la hoja: la hoja ya se cerró, y lo
/// que se abre después —revisar lo que propuso la IA, el aviso con «Ver»— va
/// sobre la pantalla.
Future<void> startCreate(
  BuildContext context,
  WidgetRef ref,
  CreateTarget target,
  CreateKind kind,
) async {
  final itemId = target.item.id;
  final runs = ref.read(createRunsProvider(itemId).notifier);
  switch (kind) {
    case CreateKind.organize:
      await organizeNowWithAi(context, ref, itemId: itemId);
    case CreateKind.dates:
      await findDatesNowWithAi(
        context,
        ref,
        itemIds: [itemId],
        seeItemId: itemId,
      );
    case CreateKind.flashcards:
      await runs.run(
        kind,
        (run) => createFlashcardsWithAi(context, ref, target, run),
      );
    case CreateKind.quiz:
      await runs.run(kind, (run) => _createQuiz(context, ref, target, run));
    case CreateKind.derivedNote:
      await runs.run(
        kind,
        (run) => _createDerivedNote(context, ref, target, run),
      );
    case CreateKind.card:
      await runs.run(
        kind,
        (run) => addFlashcardByHand(context, ref, target, run),
      );
    case CreateKind.note:
      await _writeNote(context, ref, target);
    case CreateKind.link:
      await addRelationFlow(context, ref, fromItemId: itemId);
  }
}

// --- Tarjetas de repaso -----------------------------------------------------

/// Agrega una tarjeta a mano, en la forma que se elija (F31): pregunta y
/// respuesta, dos direcciones, huecos, «escribí la respuesta» u opción
/// múltiple; o pide huecos a la IA, que trabaja como [run].
Future<void> addFlashcardByHand(
  BuildContext context,
  WidgetRef ref,
  CreateTarget target,
  CreateRun run,
) async {
  final l10n = AppLocalizations.of(context)!;
  final result = await showCardFormDialog(context, aiAvailable: true);
  if (result == null || !context.mounted) return;

  switch (result) {
    case CardFormAiRequested():
      await createFlashcardsWithAi(context, ref, target, run, cloze: true);
    case CardFormSubmitted(:final form):
      final saved = await ref.read(createCardsFromFormProvider)(
        itemId: target.item.id,
        form: form,
      );
      if (!context.mounted) return;
      saved.match(
        (failure) => _say(context, failure.localizedMessage(l10n)),
        (_) {},
      );
  }
}

/// Propone tarjetas con el modelo de lenguaje y deja que la persona elija
/// cuáles guardar.
///
/// El texto se lee **por partes** (`generateFlashcardsByParts`, F30): el
/// modelo acepta unas 2.000 palabras entre todo, y un libro o un video largo
/// mandado entero fallaba. Cada parte que se lee se cuenta en [run], que la
/// hoja y el ✨ muestran; cancelar corta antes de la próxima. Si el modelo
/// falla en el medio, se ofrece lo que alcanzó a proponer y se dice qué pasó:
/// que falta bajarlo, o que falló.
///
/// En un documento procesado salen de su texto procesado (F41, decisión K)
/// —el de sus tarjetas, `readProcessedCardText`, el mismo de la IA que
/// organiza— y no de la fuente.
///
/// Con [cloze] pide frases con huecos en vez de preguntas y respuestas (F31):
/// el mismo recorrido por partes, otra revisión y otro guardado.
Future<void> createFlashcardsWithAi(
  BuildContext context,
  WidgetRef ref,
  CreateTarget target,
  CreateRun run, {
  bool cloze = false,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final item = target.item;
  // Trabajando desde ya: averiguar de qué texto salen también espera.
  run.working();
  // Sus tarjetas no llevan pasaje: el procesado no tiene una forma de texto
  // donde «Ver en la fuente» caiga, y la de la fuente es de otro elemento.
  final read = target.processed
      ? await readProcessedCardText(
          ref.read(processedRepositoryProvider),
          item.id,
        )
      : null;
  if (!context.mounted || run.cancelled) return;
  // Si el texto procesado no se puede leer, se dice: no se cae al de la
  // fuente.
  if (read?.getLeft().toNullable() case final failure?) {
    _say(context, failure.localizedMessage(l10n));
    return;
  }
  final processed = read?.getRight().toNullable();
  // Si no, el mismo texto que abre la lectura —la forma principal que no es
  // de bloques—: el rango de una cita tiene que ser de ESE texto para que
  // «Ver en la fuente» caiga en el lugar. Sin él —una nota de bloques—, el
  // texto que se buscó siempre y sin fragmentos.
  final sourceText = target.processed
      ? null
      : extractableRendition(item)?.content;
  final content = target.processed
      ? processed?.content ?? ''
      : sourceText ?? item.searchableText;
  if (content.trim().isEmpty) {
    _say(
      context,
      cloze ? l10n.cardFormAiNoContent : l10n.flashcardsNoContentToGenerate,
    );
    return;
  }

  // Lo que el elemento ya tiene no se vuelve a proponer.
  final existing =
      ref.read(itemFlashcardsProvider(item.id)).valueOrNull ??
      const <Flashcard>[];
  final known = {
    for (final card in existing) flashcardRejectionFingerprint(card.front),
  };
  final proposed = <PartDraft>[];
  final telemetry = ref.read(telemetryServiceProvider);
  Object? failure;
  try {
    await generateFlashcardsByParts(
      generator: cloze
          ? ClozeAsFlashcardGenerator(ref.read(clozeGeneratorProvider))
          : ref.read(flashcardGeneratorProvider),
      text: content,
      wanted: math.max(kManualFlashcardsWanted, flashcardTargetFor(content)),
      // Partes del largo que lee el modelo elegido (F32).
      budget: ref.read(languageModelTextBudgetProvider)(),
      onDraft: (candidate) async {
        run.throwIfCancelled();
        if (!known.add(flashcardRejectionFingerprint(candidate.draft.front))) {
          return PartDraftOutcome.skipped;
        }
        proposed.add(candidate);
        return PartDraftOutcome.kept;
      },
      onProgress: run.progress,
    );
    // Cancelar no es un fallo: no se ofrece nada ni se dice nada.
  } on CreateCancelled {
    rethrow;
    // El generador es de terceros (flutter_gemma) y falla de formas sin un
    // tipo propio en Dart —memoria insuficiente, una sesión que se cerró—. Se
    // registra y se le cuenta a la persona; lo que ya propuso, queda.
  } on Object catch (e, stackTrace) {
    failure = e;
    if (e is! ChatModelNotReadyException) {
      telemetry.recordError(e, stackTrace, hint: 'Crear: tarjetas con IA');
    }
  }
  if (!context.mounted || run.cancelled) return;
  ref.read(createRunsProvider(item.id).notifier).idle(run);

  if (proposed.isEmpty) {
    _sayFlashcardsFailure(context, failure, nothing: true);
    return;
  }
  if (failure != null) _sayFlashcardsFailure(context, failure, nothing: false);

  final accepted = await showDialog<List<PartDraft>>(
    context: context,
    builder: (context) => cloze
        ? ClozeDraftReviewDialog(drafts: proposed)
        : FlashcardDraftReviewDialog(drafts: proposed),
  );
  if (accepted == null || accepted.isEmpty || !context.mounted) return;

  if (cloze) {
    await _saveClozeDrafts(context, ref, item.id, accepted, sourceText != null);
    return;
  }

  final repository = ref.read(flashcardRepositoryProvider);
  for (final candidate in accepted) {
    // El pasaje del que sale, si la cita se ubicó —aunque el modelo la haya
    // parafraseado—. Si no, la tarjeta se guarda igual, sin fragmento: la
    // persona la leyó y la eligió.
    final anchor = sourceText == null ? null : candidate.anchor;
    final saved = await repository.create(
      itemId: item.id,
      front: candidate.draft.front,
      back: candidate.draft.back,
      sourceCharStart: anchor?.start,
      sourceCharEnd: anchor?.end,
    );
    if (!context.mounted) return;
    final error = saved.getLeft().toNullable();
    if (error != null) {
      _say(context, error.localizedMessage(l10n));
      return;
    }
  }
}

/// Guarda las frases con huecos que la persona aceptó: cada una son las
/// tarjetas de sus huecos, enteras o ninguna, con el pasaje de la fuente del
/// que salen si se ubicó.
Future<void> _saveClozeDrafts(
  BuildContext context,
  WidgetRef ref,
  String itemId,
  List<PartDraft> accepted,
  bool hasSourceText,
) async {
  final l10n = AppLocalizations.of(context)!;
  final create = ref.read(createCardsFromFormProvider);
  var saved = 0;
  for (final candidate in accepted) {
    final anchor = hasSourceText ? candidate.anchor : null;
    final result = await create(
      itemId: itemId,
      form: ClozeCardForm(text: candidate.draft.front),
      sourceCharStart: anchor?.start,
      sourceCharEnd: anchor?.end,
    );
    if (!context.mounted) return;
    final error = result.getLeft().toNullable();
    if (error != null) {
      _say(context, error.localizedMessage(l10n));
      return;
    }
    saved += result.getRight().toNullable()!.length;
  }
  _say(context, l10n.cardFormAiSavedCount(saved));
}

/// Por qué no hubo tarjetas —o no todas—: falta bajar el modelo, el modelo
/// falló, o no propuso nada que sirviera.
void _sayFlashcardsFailure(
  BuildContext context,
  Object? failure, {
  required bool nothing,
}) {
  final l10n = AppLocalizations.of(context)!;
  if (failure is ChatModelNotReadyException) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        AppSnackBar(
          content: Text(l10n.flashcardsModelMissing),
          action: SnackBarAction(
            label: l10n.flashcardsDownloadModel,
            onPressed: () => context.push(RoutePaths.chatModel),
          ),
        ),
      );
    return;
  }
  _say(context, switch ((failure, nothing)) {
    (null, _) => l10n.flashcardsGenerationEmpty,
    (_, true) => l10n.flashcardsGenerationFailed,
    (_, false) => l10n.flashcardsGenerationPartial,
  });
}

// --- Cuestionario -----------------------------------------------------------

/// «Cuestionario» (F20): sin el modelo listo se avisa y se ofrece bajarlo
/// antes de generar nada. Lo generado se revisa antes de guardarlo, y el
/// aviso ofrece practicarlo.
///
/// Es un solo pedido al modelo: cancelar descarta lo que llegue.
Future<void> _createQuiz(
  BuildContext context,
  WidgetRef ref,
  CreateTarget target,
  CreateRun run,
) async {
  final l10n = AppLocalizations.of(context)!;
  final ready = await ensureLanguageModelReady(
    context,
    ref,
    downloadMessage: l10n.quizModelRequired,
    downloadLabel: l10n.derivedNoteDownloadAction,
  );
  if (!ready || !context.mounted) return;

  run.working();
  final result = await ref
      .read(generateQuizUseCaseProvider)
      .generate(item: target.item);
  if (!context.mounted || run.cancelled) return;
  ref.read(createRunsProvider(target.item.id).notifier).idle(run);

  final questions = result.getRight().toNullable();
  if (questions == null) {
    final failure = result.getLeft().toNullable()!;
    _say(context, failure.localizedMessage(l10n));
    return;
  }
  if (questions.isEmpty) {
    _say(context, l10n.quizGenerationFailed);
    return;
  }

  final saved = await Navigator.of(context).push<List<Flashcard>>(
    MaterialPageRoute(
      builder: (context) =>
          QuizReviewScreen(item: target.item, questions: questions),
    ),
  );
  if (saved == null || saved.isEmpty || !context.mounted) return;

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      AppSnackBar(
        content: Text(l10n.quizSaved(saved.length)),
        action: SnackBarAction(
          label: l10n.quizSessionPracticeNow,
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (context) => QuizSessionScreen(cards: saved),
            ),
          ),
        ),
      ),
    );
}

// --- Nota derivada ----------------------------------------------------------

/// «Nota derivada» (F16, D5): sin el modelo listo se avisa y se ofrece bajarlo
/// ANTES de elegir el tipo —no tiene sentido elegir algo que no va a poder
/// correr—; después, el tipo, y la IA la escribe por partes, que se cuentan en
/// [run]. La nota se guarda sola, con «Ver» en el aviso.
///
/// Cancelar corta antes de la próxima parte y antes de guardar: nada queda a
/// medias.
Future<void> _createDerivedNote(
  BuildContext context,
  WidgetRef ref,
  CreateTarget target,
  CreateRun run,
) async {
  final l10n = AppLocalizations.of(context)!;
  final ready = await ensureLanguageModelReady(
    context,
    ref,
    downloadMessage: l10n.derivedNoteModelRequired,
    downloadLabel: l10n.derivedNoteDownloadAction,
  );
  if (!ready || !context.mounted) return;

  final type = await _pickDerivedNoteType(context);
  if (type == null || !context.mounted) return;

  run.working();
  final sourceTitle = target.item.title;
  // El que escribe de verdad —Gemma o el de la nube— (F32).
  final model = ref.read(languageModelNameProvider)();
  final result = await ref.read(generateDerivedNoteUseCaseProvider)(
    GenerateDerivedNoteParams(
      type: type,
      title: _derivedNoteTitle(l10n, type, sourceTitle),
      model: model,
      itemId: target.item.id,
      // Antes de cada parte y antes de guardar: el punto de corte.
      onProgress: run.progress,
    ),
  );
  if (!context.mounted || run.cancelled) return;

  result.match((failure) => _say(context, failure.localizedMessage(l10n)), (
    result,
  ) {
    final saved = result.note;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        AppSnackBar(
          content: Text(l10n.derivedNoteCreated(saved.title)),
          action: SnackBarAction(
            label: l10n.derivedNoteViewAction,
            onPressed: () {
              if (context.mounted) {
                unawaited(context.push(RoutePaths.itemDetail(saved.id)));
              }
            },
          ),
        ),
      );
  });
}

/// Los cuatro tipos de nota derivada, en una hoja.
Future<DerivedNoteType?> _pickDerivedNoteType(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  return showModalBottomSheet<DerivedNoteType>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final type in DerivedNoteType.values)
            ListTile(
              key: Key('derived-note-type-${type.name}'),
              leading: const Icon(Icons.auto_awesome_outlined),
              title: Text(switch (type) {
                DerivedNoteType.studyGuide => l10n.derivedNoteTypeStudyGuide,
                DerivedNoteType.openQuestions =>
                  l10n.derivedNoteTypeOpenQuestions,
                DerivedNoteType.outline => l10n.derivedNoteTypeOutline,
                DerivedNoteType.timeline => l10n.derivedNoteTypeTimeline,
              }),
              onTap: () => Navigator.of(sheetContext).pop(type),
            ),
        ],
      ),
    ),
  );
}

/// El título de la nota nueva: el tipo y de qué sale.
String _derivedNoteTitle(
  AppLocalizations l10n,
  DerivedNoteType type,
  String sourceTitle,
) => switch (type) {
  DerivedNoteType.studyGuide => l10n.derivedNoteTitleStudyGuide(sourceTitle),
  DerivedNoteType.openQuestions => l10n.derivedNoteTitleOpenQuestions(
    sourceTitle,
  ),
  DerivedNoteType.outline => l10n.derivedNoteTitleOutline(sourceTitle),
  DerivedNoteType.timeline => l10n.derivedNoteTitleTimeline(sourceTitle),
};

// --- Nota a mano ------------------------------------------------------------

/// «Nota» a mano: la persona la escribe y va a la sección Notas del documento
/// procesado, como lo que se extrae de él. El aviso trae «Deshacer», que la
/// saca sola.
Future<void> _writeNote(
  BuildContext context,
  WidgetRef ref,
  CreateTarget target,
) async {
  final l10n = AppLocalizations.of(context)!;
  final text = await showDialog<String>(
    context: context,
    builder: (_) => const WriteNoteDialog(),
  );
  if (text == null || !context.mounted) return;
  // Lo que se usa después de esperar se toma ahora: el aviso puede tocarse
  // cuando la pantalla ya no está.
  final messenger = ScaffoldMessenger.of(context);
  final notes = ref.read(extractNoteToProcessedProvider);
  final saved = await notes.write(documentId: target.item.id, text: text);
  if (!context.mounted) return;
  saved.match((failure) => _say(context, failure.localizedMessage(l10n)), (
    outcome,
  ) {
    if (outcome is! ExtractedToProcessed) return;
    if (outcome.unchanged) {
      _say(context, l10n.processedCutRepeated);
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        AppSnackBar(
          content: Text(l10n.f45S7bNoteAdded),
          action: SnackBarAction(
            label: l10n.inboxUndo,
            onPressed: () => unawaited(() async {
              final undone = await notes.undo(outcome.undo);
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(
                      undone.match(
                        (failure) => failure.localizedMessage(l10n),
                        (_) => l10n.processedNoteUndone,
                      ),
                    ),
                  ),
                );
            }()),
          ),
        ),
      );
  });
}

void _say(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
