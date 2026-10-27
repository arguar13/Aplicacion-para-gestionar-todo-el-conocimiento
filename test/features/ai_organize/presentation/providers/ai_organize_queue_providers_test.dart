import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_models_providers.dart';
import 'package:sinapsis/features/ai_organize/data/steps/auto_dates_step.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_dates_batch.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_dates_finder.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_queue_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_settings_notifier.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';

import '../../../../support/library_harness.dart';

/// La cola de la IA armada por sus proveedores (F32): lo que la destraba
/// cuando esperaba al modelo de lenguaje le llega solo, sin que nadie la
/// despierte a mano.
void main() {
  late LibraryHarness harness;

  AiOrganizeStatus status() => harness.container.read(aiOrganizeStatusProvider);

  testWidgets('cargar una cuenta de la nube la destraba en el acto', (
    tester,
  ) async {
    harness = await LibraryHarness.create(
      embeddingModelReady: true,
      languageModelProvider: AiProvider.gemini,
    );
    final queue = harness.container.read(aiOrganizeQueueProvider);
    await queue.wake();
    expect(
      status(),
      isA<AiOrganizeModelMissing>().having(
        (s) => s.keyFor,
        'keyFor',
        AiProvider.gemini,
      ),
    );

    await harness.container
        .read(aiAccountRepositoryProvider)
        .add(provider: AiProvider.gemini, key: 'AIza-de-prueba');
    // La cuenta nueva llega por el flujo de las cuentas, y la cola se
    // despierta con él.
    await tester.pump();
    await queue.settled;

    expect(status(), isA<AiOrganizeIdle>());
  });

  testWidgets('elegir otro proveedor la destraba en el acto', (tester) async {
    harness = await LibraryHarness.create(
      chatModelReady: true,
      embeddingModelReady: true,
      languageModelProvider: AiProvider.gemini,
    );
    final queue = harness.container.read(aiOrganizeQueueProvider);
    await queue.wake();
    expect(status(), isA<AiOrganizeModelMissing>());

    await harness.container
        .read(aiModelSettingsProvider.notifier)
        .chooseProvider(AiProvider.gemma);
    await tester.pump();
    await queue.settled;

    // Gemma está bajado: ya no falta nada.
    expect(status(), isA<AiOrganizeIdle>());
    // Los pasos de la IA miran el nombre del modelo elegido: Riverpod los
    // rearma con un timer en cero, que solo corre si avanza el reloj.
    await tester.pump(Duration.zero);
  });

  group('las fechas para la línea de tiempo (F40)', () {
    testWidgets('el paso de fechas está entre los de la cola, antes de las '
        'tarjetas y del Atlas, y también sirve para pedirlas solas', (
      tester,
    ) async {
      harness = await LibraryHarness.create();
      final steps = harness.container.read(aiOrganizeStepsProvider);

      final toggles = [for (final step in steps) step.toggle];
      expect(toggles, contains(AiOrganizeToggle.dates));
      expect(
        toggles.indexOf(AiOrganizeToggle.dates),
        lessThan(toggles.indexOf(AiOrganizeToggle.flashcards)),
      );
      expect(
        toggles.indexOf(AiOrganizeToggle.flashcards),
        lessThan(toggles.indexOf(AiOrganizeToggle.atlas)),
      );
      final dates = steps.whereType<AutoDatesStep>().single;
      expect(dates, isA<AiDatesFinder>());
      expect(dates.toggle, AiOrganizeToggle.dates);
      await tester.pump(Duration.zero);
    });

    testWidgets('pedirlas publica cómo va el pedido; un texto sin fechas no '
        'abre una pasada ni usa el modelo', (tester) async {
      harness = await LibraryHarness.create(chatModelReady: true);
      final now = DateTime(2026, 9, 11, 10);
      await harness.container
          .read(libraryRepositoryProvider)
          .save(
            KnowledgeItem(
              id: 'receta',
              title: 'Una receta',
              source: Source(
                id: 'src',
                kind: SourceKind.webPage,
                capturedAt: now,
                url: 'https://e.org/receta',
              ),
              processingState: ProcessingState.ready,
              createdAt: now,
              updatedAt: now,
              renditions: [
                Rendition.text(
                  id: 'rend',
                  itemId: 'receta',
                  kind: RenditionKind.plainText,
                  content: 'Harina, agua y sal. Se amasa y se hornea.',
                  isPrimary: true,
                  createdAt: now,
                ),
              ],
            ),
          );
      final queue = harness.container.read(aiOrganizeQueueProvider)
        ..findDates(['receta']);
      await queue.settled;

      expect(
        harness.container.read(aiDatesBatchProvider),
        const AiDatesBatch(total: 1, done: 1),
      );
      final runs = await harness.container
          .read(aiRunRepositoryProvider)
          .listRuns();
      expect(runs.getRight().toNullable(), isEmpty);
      await tester.pump(Duration.zero);
    });
  });
}
