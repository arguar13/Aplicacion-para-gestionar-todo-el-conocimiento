import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_label.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_thinking.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_models_providers.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';

/// Si el modelo que escribe ahora puede «pensar más» (F42) y cómo se llama,
/// para el interruptor de la hoja «Agregar al chat»: prendible, o apagado
/// diciendo por qué. Al día con el proveedor y el modelo elegidos.
final chatThinkMoreSupportProvider =
    Provider.autoDispose<({ThinkMoreSupport support, String model})>((ref) {
      final provider = ref.watch(
        aiModelSettingsProvider.select((settings) => settings.provider),
      );
      final model = ref.watch(chosenLanguageModelNameProvider);
      return (
        support: thinkMoreSupport(provider, model),
        model: modelLabel(model),
      );
    });
