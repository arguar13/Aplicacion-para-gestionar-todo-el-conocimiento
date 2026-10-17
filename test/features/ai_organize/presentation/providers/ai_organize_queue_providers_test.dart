import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_models_providers.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_queue_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_settings_notifier.dart';

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
}
