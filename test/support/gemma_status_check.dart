import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model_manager.dart';

/// El chequeo del modelo de lenguaje con Gemma elegido (F32), como lo
/// contesta `AiLanguageModelReadiness`: listo si [manager] está bajado; si
/// no, falta bajarlo. Para las pruebas que arman la cola de la IA sin la
/// cadena de proveedores.
LanguageModelStatusCheck gemmaStatusCheck(ChatModelManager manager) =>
    ({bool background = false}) async => await manager.isReady()
    ? const LanguageModelReady(provider: AiProvider.gemma)
    : const LanguageModelNeedsDownload();
