import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_queue_providers.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/flashcard_coverage_reader.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/ai_flashcards_providers.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/notebooks/domain/repositories/notebook_repository.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/features/notes/domain/services/derived_note_generator.dart';
import 'package:sinapsis/features/notes/domain/usecases/generate_derived_note_usecase.dart';
import 'package:sinapsis/features/notes/presentation/providers/derived_note_providers.dart';

/// Qué pasó con las tarjetas pedidas para el cuaderno.
@immutable
class FillCardsOutcome {
  const FillCardsOutcome({
    required this.queued,
    required this.eligible,
    this.failure,
  });

  /// De cuántos elementos se pidieron tarjetas a la cola de la IA.
  final int queued;

  /// Cuántos elementos del cuaderno pueden tener tarjetas (tienen texto).
  final int eligible;

  /// Por qué no se pudo contar, si no se pudo.
  final Failure? failure;

  /// Si todo lo que puede tener tarjetas ya las tiene.
  bool get alreadyHadAll => failure == null && eligible > 0 && queued == 0;

  /// Si nada tiene texto de donde sacar tarjetas.
  bool get nothingToMake => failure == null && eligible == 0;
}

/// Qué pasó con la nota derivada del cuaderno.
@immutable
class FillGuideOutcome {
  const FillGuideOutcome({this.result, this.failure});

  final DerivedNoteResult? result;
  final Failure? failure;
}

@immutable
class FillNotebookState {
  const FillNotebookState({
    this.guide = true,
    this.cards = true,
    this.type = DerivedNoteType.studyGuide,
    this.running = false,
    this.partsRead = 0,
    this.partsTotal = 0,
    this.cardsOutcome,
    this.guideOutcome,
    this.finished = false,
  });

  /// Si se pide la nota (guía de estudio u otro tipo) y/o las tarjetas.
  final bool guide;
  final bool cards;
  final DerivedNoteType type;

  final bool running;

  /// Cuántas partes de las fuentes leyó el modelo, de cuántas: la nota de un
  /// cuaderno grande se lee en varios pedidos.
  final int partsRead;
  final int partsTotal;

  final FillCardsOutcome? cardsOutcome;
  final FillGuideOutcome? guideOutcome;
  final bool finished;

  bool get canStart => !running && !finished && (guide || cards);

  FillNotebookState copyWith({
    bool? guide,
    bool? cards,
    DerivedNoteType? type,
    bool? running,
    int? partsRead,
    int? partsTotal,
    FillCardsOutcome? cardsOutcome,
    FillGuideOutcome? guideOutcome,
    bool? finished,
  }) => FillNotebookState(
    guide: guide ?? this.guide,
    cards: cards ?? this.cards,
    type: type ?? this.type,
    running: running ?? this.running,
    partsRead: partsRead ?? this.partsRead,
    partsTotal: partsTotal ?? this.partsTotal,
    cardsOutcome: cardsOutcome ?? this.cardsOutcome,
    guideOutcome: guideOutcome ?? this.guideOutcome,
    finished: finished ?? this.finished,
  );
}

/// «Llenar» un cuaderno (F30, decisión B): una nota derivada —por defecto, la
/// guía de estudio— que **queda adentro del cuaderno**, y las tarjetas de
/// repaso de lo que tiene.
///
/// Primero se piden las tarjetas, que no esperan: van a la cola de la IA
/// (`AiOrganizeQueue.makeFlashcards`), solo de los elementos del cuaderno que
/// todavía no tienen. Se cuentan **antes** de crear la nota: la guía es un
/// derivado de lo que ya está, y no tiene que dar tarjetas de tarjetas.
/// Después se genera la nota, por partes y con progreso, con el turno de la
/// persona: la cola, si estaba haciendo tarjetas, se corta y sigue después.
class FillNotebookController extends StateNotifier<FillNotebookState> {
  FillNotebookController({
    required this.notebookId,
    required NotebookRepository notebooks,
    required LibraryRepository library,
    required FlashcardCoverageReader coverage,
    required void Function(Iterable<String> itemIds) makeFlashcards,
    required Future<Either<Failure, DerivedNoteResult>> Function(
      GenerateDerivedNoteParams params,
    )
    generate,
  }) : _notebooks = notebooks,
       _library = library,
       _coverage = coverage,
       _makeFlashcards = makeFlashcards,
       _generate = generate,
       super(const FillNotebookState());

  final String notebookId;
  final NotebookRepository _notebooks;
  final LibraryRepository _library;
  final FlashcardCoverageReader _coverage;
  final void Function(Iterable<String> itemIds) _makeFlashcards;
  final Future<Either<Failure, DerivedNoteResult>> Function(
    GenerateDerivedNoteParams params,
  )
  _generate;

  void setGuide({required bool value}) {
    if (!state.running) state = state.copyWith(guide: value);
  }

  void setCards({required bool value}) {
    if (!state.running) state = state.copyWith(cards: value);
  }

  void setType(DerivedNoteType type) {
    if (!state.running) state = state.copyWith(type: type);
  }

  /// Hace lo elegido. [guideTitle] y [model] los pone quien lo pide: el título
  /// va traducido y el modelo es el que está activo ahora.
  Future<void> start({
    required String guideTitle,
    required String model,
  }) async {
    if (!state.canStart) return;
    state = state.copyWith(running: true);

    if (state.cards) {
      final outcome = await _requestCards();
      if (!mounted) return;
      state = state.copyWith(cardsOutcome: outcome);
    }

    if (state.guide) {
      final result = await _generate(
        GenerateDerivedNoteParams(
          type: state.type,
          title: guideTitle,
          model: model,
          notebookId: notebookId,
          onProgress: (read, total) {
            if (mounted) {
              state = state.copyWith(partsRead: read, partsTotal: total);
            }
          },
        ),
      );
      if (!mounted) return;
      state = state.copyWith(
        guideOutcome: FillGuideOutcome(
          result: result.getRight().toNullable(),
          failure: result.getLeft().toNullable(),
        ),
      );
    }

    if (mounted) state = state.copyWith(running: false, finished: true);
  }

  /// Pide tarjetas de lo del cuaderno que puede tenerlas y todavía no las
  /// tiene.
  Future<FillCardsOutcome> _requestCards() async {
    final query = await _notebooks.resolveQuery(notebookId);
    final ids = await _library.matchingIds(query);
    final failure = ids.getLeft().toNullable();
    if (failure != null) {
      return FillCardsOutcome(queued: 0, eligible: 0, failure: failure);
    }
    final coverage = await _coverage.coverageOf(ids.getRight().toNullable());
    final covered = coverage.getRight().toNullable();
    if (covered == null) {
      return FillCardsOutcome(
        queued: 0,
        eligible: 0,
        failure: coverage.getLeft().toNullable(),
      );
    }
    final missing = covered.withoutCards;
    if (missing.isNotEmpty) _makeFlashcards(missing);
    return FillCardsOutcome(
      queued: missing.length,
      eligible: covered.eligible.length,
    );
  }
}

/// «Llenar» un cuaderno, por su id, mientras su hoja está abierta (F30).
final fillNotebookControllerProvider = StateNotifierProvider.autoDispose
    .family<FillNotebookController, FillNotebookState, String>(
      (ref, notebookId) => FillNotebookController(
        notebookId: notebookId,
        notebooks: ref.watch(notebookRepositoryProvider),
        library: ref.watch(libraryRepositoryProvider),
        coverage: ref.watch(flashcardCoverageReaderProvider),
        makeFlashcards: ref.read(aiOrganizeQueueProvider).makeFlashcards,
        generate: (params) =>
            ref.read(generateDerivedNoteUseCaseProvider)(params),
      ),
    );
