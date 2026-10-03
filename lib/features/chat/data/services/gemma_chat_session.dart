import 'dart:typed_data';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_gate.dart';

/// Cuánto de lo conversado se le vuelve a dar al modelo al retomar una charla
/// cuya sesión se cerró por falta de uso (F27): los últimos intercambios que
/// entren. 2400 caracteres son ~690 tokens; con el mensaje nuevo, el
/// contexto de la bóveda que lo acompañe y la respuesta, entra en la ventana
/// de 2048.
const kResumedTranscriptChars = 2400;

/// La sesión de una charla sobre `flutter_gemma`, que se mantiene abierta
/// entre mensajes —el modelo ve todo lo dicho antes— y retiene el modelo
/// mientras esté en uso (F27, `LanguageModelGate.holdForUser`).
///
/// Si pasa un rato sin uso y sin la pantalla a la vista, la sesión se cierra
/// y el modelo pasa a la cola de la IA. El próximo mensaje la reabre y le da,
/// junto con él, lo conversado hasta ahí (los últimos intercambios que entren
/// en [kResumedTranscriptChars]): un solo mensaje de la persona, porque así
/// lo entienden todos los formatos de `flutter_gemma` —un turno del modelo
/// agregado a mano no lo leen igual un `.task` y un `.litertlm`—.
class GemmaChatSession {
  GemmaChatSession(this._gate, this._open) {
    _hold = _gate.holdForUser(onIdle: _closeForIdle);
  }

  final LanguageModelGate _gate;

  /// Abre una sesión nueva con la instrucción de la charla. Corre dentro del
  /// turno de la persona: no lo pide.
  final Future<InferenceChat> Function() _open;

  late final LanguageModelHold _hold;
  InferenceChat? _chat;

  /// Si la sesión se cerró por falta de uso: el próximo mensaje lleva lo
  /// conversado.
  var _resuming = false;

  /// Lo que se dijo, de a intercambios: lo que escribió la persona —sin el
  /// contexto de la bóveda, que se busca de nuevo— y lo que contestó el
  /// modelo.
  final _turns = <({String said, String answer})>[];

  /// Abre la primera sesión. Si falla, suelta el modelo.
  Future<void> openFirst() async {
    try {
      _chat = await _gate.runForUser(_open);
    } on Object {
      _hold.release();
      rethrow;
    }
  }

  /// Manda [prompt] —lo que [said] la persona, con lo que lo acompañe— y
  /// espera la respuesta. Cuenta como uso al mandarlo y al recibirla.
  Future<String> send({
    required String prompt,
    required String said,
    List<Uint8List> images = const [],
  }) async {
    _hold.touch();
    try {
      final answer = await _gate.runForUser(() async {
        final chat = _chat ??= await _open();
        final text = _resuming ? _withTranscript(prompt) : prompt;
        await chat.addQueryChunk(
          images.isEmpty
              ? Message.text(text: text, isUser: true)
              : Message.withImages(
                  text: text,
                  imageBytes: images,
                  isUser: true,
                ),
        );
        _resuming = false;
        final response = await chat.generateChatResponse();

        return switch (response) {
          TextResponse(:final token) => token,
          _ => '',
        };
      });
      _turns.add((
        said: images.isEmpty ? said : '$said [con ${images.length} foto(s)]',
        answer: answer,
      ));
      return answer;
    } finally {
      _hold.touch();
    }
  }

  Future<void> close() async {
    try {
      final chat = _chat;
      _chat = null;
      await chat?.close();
    } finally {
      _hold.release();
    }
  }

  /// La charla lleva un rato sin uso: cierra la sesión para que la cola de la
  /// IA pueda abrir la suya. Corre en un turno de la persona.
  Future<void> _closeForIdle() async {
    final chat = _chat;
    if (chat == null) return;
    _chat = null;
    _resuming = true;
    await chat.close();
  }

  /// [prompt] con lo conversado antes delante: los últimos intercambios que
  /// entren en [kResumedTranscriptChars]; si ni el último entra, su final.
  String _withTranscript(String prompt) {
    if (_turns.isEmpty) return prompt;
    final lines = <String>[];
    var used = 0;
    for (final turn in _turns.reversed) {
      final line = 'Persona: ${turn.said}\nAsistente: ${turn.answer}';
      if (used + line.length > kResumedTranscriptChars) {
        if (lines.isEmpty) {
          lines.add(line.substring(line.length - kResumedTranscriptChars));
        }
        break;
      }
      lines.insert(0, line);
      used += line.length + 2;
    }
    return 'Lo que veníamos conversando:\n\n${lines.join('\n\n')}'
        '\n\n---\n\n$prompt';
  }
}
