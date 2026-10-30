import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/extracted_text_format.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_models_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_task_providers.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/processed/data/repositories/prefs_processed_tidy_store.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_tidy_store.dart';
import 'package:sinapsis/features/processed/domain/services/processed_tidy_queue.dart';
import 'package:sinapsis/features/processed/domain/services/text_tidier.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';

/// Quien ordena el texto al triar (F45, decisión B): el modelo de la persona,
/// con el turno de la cola —espera a que no lo use— y gastando de su cuota,
/// como «Revisar con otro modelo» (F33): lo pidió ella.
final textTidierProvider = Provider<TextTidier>(
  (ref) => ref.watch(requestedBackgroundLanguageModelProvider),
);

/// Dónde esperan los pedidos de ordenar: en el teléfono.
final processedTidyStoreProvider = Provider<ProcessedTidyStore>(
  (ref) => PrefsProcessedTidyStore(ref.watch(sharedPreferencesProvider)),
);

/// La cola que ordena el texto de lo que se acaba de triar.
///
/// Deliberadamente NO autoDispose y sin `ref.watch` —como la de «Lo
/// creado»—: tiene que seguir aunque la persona cambie de pantalla, y cambiar
/// de modelo no puede descartarla con lo que tenía esperando. Sus
/// dependencias se leen al usarlas.
final processedTidyQueueProvider = Provider<ProcessedTidyQueue>((ref) {
  final queue = ProcessedTidyQueue(
    repository: () => ref.read(processedRepositoryProvider),
    tidier: () => ref.read(textTidierProvider),
    store: ref.read(processedTidyStoreProvider),
    readiness: () => ref.read(languageModelStatusCheckProvider),
    keeper: () =>
        ref.read(longWorkCoordinatorProvider).keeperFor(LongWorkOwner.tidying),
    tasks: ref.read(aiTaskTrackerProvider),
    modelName: () => ref.read(languageModelNameProvider)(),
    titleOf: (documentId) async =>
        (await ref.read(libraryRepositoryProvider).findById(documentId))
            .getRight()
            .toNullable()
            ?.title,
    onError: (error, stackTrace) => ref
        .read(telemetryServiceProvider)
        .recordError(error, stackTrace, hint: 'ProcessedTidyQueue'),
  );
  ref.onDispose(queue.dispose);
  return queue;
});

/// Qué pasa con el texto extraído de una fuente al triarla con la IA (F45,
/// decisión B): lo que la hoja «¿Qué va a Procesado?» dice al prenderlo.
@immutable
sealed class TriageTidyOffer {
  const TriageTidyOffer();
}

/// Lo ordena la IA de turno: [model], como lo guardan las pasadas, en la
/// nube o en el teléfono ([cloud]).
class TriageTidyBy extends TriageTidyOffer {
  const TriageTidyBy({required this.model, required this.cloud});

  final String model;
  final bool cloud;

  @override
  bool operator ==(Object other) =>
      other is TriageTidyBy && other.model == model && other.cloud == cloud;

  @override
  int get hashCode => Object.hash(model, cloud);
}

/// Va como se extrajo: la IA no está lista —falta bajar Gemma, una cuenta,
/// o no le queda cuota—.
class TriageTidyUnavailable extends TriageTidyOffer {
  const TriageTidyUnavailable();
}

/// Va como se extrajo: ya viene ordenado —una página web, un Word, un EPUB,
/// un Markdown: la app lo arma con sus títulos y sus párrafos
/// (`extractedTextIsMarkdown`)—.
class TriageTidyNotNeeded extends TriageTidyOffer {
  const TriageTidyNotNeeded();
}

/// Qué pasa con el texto de una fuente, por su id, si se lo trae con la IA;
/// `null` mientras se averigua. Cambia en vivo con el modelo elegido.
final triageTidyOfferProvider = Provider.autoDispose
    .family<TriageTidyOffer?, String>((ref, sourceItemId) {
      final item = ref.watch(libraryItemProvider(sourceItemId)).valueOrNull;
      if (item == null) return null;
      if (extractedTextIsMarkdown(item.source)) {
        return const TriageTidyNotNeeded();
      }
      final status = ref.watch(languageModelStatusProvider);
      if (status.isLoading && !status.hasValue) return null;
      if (!(status.valueOrNull?.isReady ?? false)) {
        return const TriageTidyUnavailable();
      }
      return TriageTidyBy(
        model: ref.watch(chosenLanguageModelNameProvider),
        cloud: ref
            .watch(aiModelSettingsProvider.select((s) => s.provider))
            .isCloud,
      );
    });
