import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:sinapsis/features/chat/data/services/gemma_chat_session.dart';
import 'package:sinapsis/features/chat/data/services/gemma_engine.dart';
import 'package:sinapsis/features/chat/data/services/gemma_reply.dart';
import 'package:sinapsis/features/chat/domain/entities/language_model_performance.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_gate.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_meter.dart';
import 'package:sinapsis/features/chat/domain/services/model_backend.dart';

/// [ModelBackend] sobre `flutter_gemma`: Gemma corriendo en el
/// dispositivo, vía FFI directo —sin JVM, sin servidor propio, ver la
/// decisión 20 en docs/arquitectura.md—.
///
/// El modelo cargado ([GemmaEngine]) se guarda en memoria entre usos: son
/// varios cientos de megas de pesos. Lo que se abre y se cierra por pedido es
/// la sesión —barata, comparada con el modelo—, para que un pedido no
/// arrastre el historial del anterior.
class GemmaBackend implements ModelBackend {
  /// [engine] es el modelo cargado, compartido por todos los que lo usan;
  /// [meter], dónde queda lo que tardó cada respuesta (F30); [countTokens]
  /// cuenta con el tokenizador del modelo lo que ocupa un texto.
  ///
  /// [gate] lo usan las charlas ([openConversation]), que piden sus propios
  /// turnos mientras duran.
  GemmaBackend({
    required LanguageModelGate gate,
    required GemmaEngine engine,
    required LanguageModelMeter meter,
    GemmaTokenCounter countTokens = countGemmaTokens,
  }) : _gate = gate,
       _engine = engine,
       _meter = meter,
       _countTokens = countTokens;

  final LanguageModelGate _gate;
  final GemmaEngine _engine;
  final LanguageModelMeter _meter;
  final GemmaTokenCounter _countTokens;

  @override
  ModelBackend get forBackground => this;

  @override
  int get contextTokens => _engine.contextTokens;

  @override
  bool get isWarm => _engine.isLoaded;

  @override
  Future<void> warmUp() async {
    await _engine.model();
  }

  @override
  Future<ModelExchange> openExchange({
    required String instruction,
    required int maxOutputTokens,
  }) async {
    final chat = await (await _engine.model()).createChat(
      systemInstruction: instruction,
      maxOutputTokens: maxOutputTokens,
    );
    return _GemmaExchange(chat, instruction, _meter, _countTokens);
  }

  /// Una charla que deja su sesión abierta entre mensajes. Desde antes de
  /// abrirla, y mientras esté en uso, la cola de la IA no usa el modelo
  /// (F27): le cerraría la sesión a la charla. Si abrirla falla, el modelo se
  /// suelta.
  ///
  /// La sesión lleva su propia cuenta de la ventana (F30, ver
  /// [GemmaChatSession]): por eso `tokenBuffer: 0`, que apaga el recorte de
  /// `flutter_gemma` —cuenta solo lo que escribe el modelo y, al pasarse,
  /// junta todo lo conversado en un solo mensaje—.
  @override
  Future<ModelConversation> openConversation({
    required String instruction,
    required int maxOutputTokens,
  }) async {
    final session = GemmaChatSession(
      _gate,
      () async => (await _engine.model()).createChat(
        systemInstruction: instruction,
        maxOutputTokens: maxOutputTokens,
        tokenBuffer: 0,
      ),
      reply: (chat) =>
          measuredReply(chat, meter: _meter, kind: LanguageModelReplyKind.chat),
      clean: cleanReply,
      instruction: instruction,
      window: _engine.contextTokens,
      replyTokens: maxOutputTokens,
      prepareImages: () => _engine.model(vision: true),
      loadCount: () => _engine.loadCount,
      countTokens: _countTokens,
    );
    await session.openFirst();
    return session;
  }
}

/// Un pedido de una vuelta sobre una sesión de `flutter_gemma`.
class _GemmaExchange implements ModelExchange {
  _GemmaExchange(this._chat, this._instruction, this._meter, this._count);

  final InferenceChat _chat;
  final String _instruction;
  final LanguageModelMeter _meter;
  final GemmaTokenCounter _count;

  @override
  Future<int> countTokens(String text) => _count(_chat, text);

  @override
  Future<String> reply(
    String text, {
    LanguageModelReplyKind kind = LanguageModelReplyKind.task,
  }) async {
    final inputTokens = await _inputTokens(text);
    await _chat.addQueryChunk(Message.text(text: text, isUser: true));
    return collectReply(
      _chat,
      meter: _meter,
      kind: kind,
      inputTokens: inputTokens,
    );
  }

  /// Lo que lee el modelo para contestar [text]: la instrucción —la primera
  /// vez que se le habla— y el pedido, con su tokenizador (F39). Es lo que
  /// gastó la tarea de ese lado; si no se pudo contar, no se anota nada en
  /// lugar de estimarlo.
  Future<int?> _inputTokens(String text) async {
    try {
      var tokens = await _count(_chat, text);
      if (!_instructionCounted) {
        tokens += await _count(_chat, _instruction);
        _instructionCounted = true;
      }
      return tokens;
      // El tokenizador es de `flutter_gemma`, que falla de formas sin un tipo
      // propio; contar no puede romper la respuesta.
    } on Object {
      return null;
    }
  }

  var _instructionCounted = false;

  @override
  Future<void> stop() => _chat.stopGeneration();

  @override
  Future<void> close() => _chat.close();
}
