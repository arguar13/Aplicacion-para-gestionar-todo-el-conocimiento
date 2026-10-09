import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/flashcards/data/repositories/cloze_card_editor_impl.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/cloze_card_editor.dart';
import 'package:sinapsis/features/flashcards/domain/usecases/create_cards_from_form_usecase.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';

/// Crea las tarjetas de lo que se llenó en el formulario (F31).
final createCardsFromFormProvider = Provider<CreateCardsFromFormUseCase>(
  (ref) => CreateCardsFromFormUseCase(ref.watch(flashcardRepositoryProvider)),
);

/// Edita el texto de una tarjeta de huecos junto con sus hermanas (F31).
final clozeCardEditorProvider = Provider<ClozeCardEditor>(
  (ref) => ClozeCardEditorImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
  ),
);
