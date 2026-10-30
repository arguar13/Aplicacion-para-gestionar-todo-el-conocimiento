import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/illustration_providers.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_generator.dart';
import 'package:sinapsis/features/creations/flashcards/data/service_study_illustrator.dart';
import 'package:sinapsis/features/creations/flashcards/domain/deck_review.dart';
import 'package:sinapsis/features/creations/flashcards/domain/flashcard_deck_generator.dart';
import 'package:sinapsis/features/creations/flashcards/domain/flashcard_deck_prompt.dart';
import 'package:sinapsis/features/creations/flashcards/domain/item_illustrations.dart';
import 'package:sinapsis/features/creations/flashcards/presentation/deck_each_document.dart';
import 'package:sinapsis/features/creations/flashcards/presentation/export/flashcard_deck_export.dart';
import 'package:sinapsis/features/creations/flashcards/presentation/widgets/flashcard_deck_viewer.dart';
import 'package:sinapsis/features/creations/flashcards/presentation/widgets/study_viewer_parts.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_illustration_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';

/// Quien dibuja las ilustraciones de las tarjetas y las preguntas, con las
/// reglas y el almacén de la infografía. Sus dependencias se leen al usarlas
/// —como la cola—: cambiar de cuenta no lo rearma.
final studyIllustratorProvider = Provider<StudyIllustrator>(
  (ref) => ServiceStudyIllustrator(
    service: () => ref.read(illustrationServiceProvider),
    store: () => ref.read(creationIllustrationStoreProvider),
    textAccountId: () => creationTextAccountId(ref),
  ).illustrate,
);

/// «Sumar a mi repaso» sobre las tarjetas de siempre.
final deckReviewProvider = Provider<DeckReview>(
  (ref) => DeckReview(flashcards: () => ref.read(flashcardRepositoryProvider)),
);

/// El generador de «Tarjetas didácticas» (F43, paso 8): su línea en
/// `creationGeneratorsProvider`.
final flashcardsGeneratorProvider = Provider<CreationGenerator>(
  (ref) => FlashcardDeckGenerator(
    review: ref.watch(deckReviewProvider),
    illustrator: () => ref.read(studyIllustratorProvider),
  ),
);

/// Cómo es «Tarjetas didácticas» en Repasar (F43, paso 8): su línea en
/// `creationKindSpecsProvider`. Las opciones de fábrica del plan —número,
/// dificultad, «Incluir imágenes», idioma, fuentes y tema—, con «Incluir
/// imágenes» como ilustraciones con IA y «Sumar a mi repaso» prendido; su
/// visor, su botón de descargar y su archivo. Con varios documentos, «Cómo»:
/// un mazo, o «Para cada documento» con la cola de la IA (M18).
final flashcardsKindSpecProvider = Provider<CreationKindSpec>((ref) {
  final base = defaultCreationKindSpec(StudyCreationKind.flashcards);
  return base.copyWith(
    options: [
      ...withIllustratedImages(
        base.options,
        hint: (l) => l.f43CardsOptImagesHint,
      ),
      CreationToggleOption(
        key: DeckOptionKeys.addToReview,
        label: (l) => l.f43CardsOptAddToReview,
        hint: (l) => l.f43CardsOptAddToReviewHint,
        initial: true,
      ),
    ],
    expectedOutputTokens: deckExpectedOutputTokens,
    illustrations: deckIllustrationCount,
    viewerBuilder: (context, creation) =>
        FlashcardDeckViewer(key: ValueKey(creation.id), creation: creation),
    viewerActions: (context, creation) => [
      StudyDownloadButton(creation: creation),
    ],
    exporter: exportFlashcardDeck,
    eachDocument: deckEachDocument,
  );
});
