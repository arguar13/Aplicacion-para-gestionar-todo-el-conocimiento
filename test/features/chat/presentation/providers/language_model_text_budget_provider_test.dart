import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_text_budget.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_models_providers.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';

import '../../../../support/library_harness.dart';

/// Cuánto lee por pedido el modelo que escribe ahora (F32), y cómo se llama:
/// lo usan las tarjetas, los derivados y lo que anota la IA.
void main() {
  testWidgets('con Gemma, lo medido para su ventana', (tester) async {
    final harness = await LibraryHarness.create();

    expect(
      harness.container.read(languageModelTextBudgetProvider)(),
      kSmallWindowTextBudget,
    );
  });

  testWidgets('con Gemini, un capítulo por pedido; y se lee al usarlo: '
      'cambiar de proveedor vale en el acto', (tester) async {
    final harness = await LibraryHarness.create(
      languageModelProvider: AiProvider.gemini,
    );
    final budget = harness.container.read(languageModelTextBudgetProvider);
    final name = harness.container.read(languageModelNameProvider);

    expect(budget().partChars, kMaxPartChars);
    expect(budget().maxDraftsPerCall, kLargeWindowDraftsPerCall);
    expect(name(), isNot('gemma4E4b'));

    await harness.container
        .read(aiModelSettingsProvider.notifier)
        .chooseProvider(AiProvider.gemma);
    expect(budget(), kSmallWindowTextBudget);
    expect(name(), 'gemma4E4b');
    // El motor se rearma con un timer en cero de Riverpod.
    await tester.pump(Duration.zero);
  });
}
