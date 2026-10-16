import 'package:sinapsis/features/chat/data/services/gemma_backend.dart';
import 'package:sinapsis/features/chat/data/services/gemma_chat_session.dart';
import 'package:sinapsis/features/chat/data/services/gemma_engine.dart';
import 'package:sinapsis/features/chat/data/services/language_model_tasks.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_meter.dart';

export 'package:sinapsis/features/chat/data/services/language_model_tasks.dart';

/// Las tareas de la app ([LanguageModelTasks]) con Gemma en el teléfono
/// ([GemmaBackend]): lo que la app hizo siempre, hasta que en F32 el motor
/// pasó a ser intercambiable.
class GemmaChatModel extends LanguageModelTasks {
  /// [engine] es el modelo cargado, compartido por todos; [meter], dónde queda
  /// lo que tardó cada respuesta (F30); [countTokens] cuenta con el
  /// tokenizador del modelo lo que ocupa un texto en la ventana.
  GemmaChatModel({
    required super.gate,
    required GemmaEngine engine,
    required LanguageModelMeter meter,
    GemmaTokenCounter countTokens = countGemmaTokens,
  }) : super(
         backend: GemmaBackend(
           gate: gate,
           engine: engine,
           meter: meter,
           countTokens: countTokens,
         ),
       );
}
