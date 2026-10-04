import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_gate.dart';

/// Lo que agrega la plantilla de la charla por cada intercambio —las marcas
/// de turno de la persona y del modelo—, con margen.
const kTurnTemplateTokens = 16;

/// Margen de la ventana que nunca se usa: lo que el tokenizador y el motor
/// puedan contar distinto.
const kWindowSafetyTokens = 32;

/// Lo que ocupa una foto en la ventana: `flutter_gemma` la cuenta como 257
/// tokens; Gemma 4 puede usar algunos más según el tamaño, y sobrar es lo
/// seguro.
const kImageTokens = 300;

/// Cuenta los tokens de [text] con el tokenizador del modelo de [chat].
typedef GemmaTokenCounter =
    Future<int> Function(InferenceChat chat, String text);

/// [GemmaTokenCounter] de verdad: el tokenizador del motor —el de
/// `.litertlm`, exacto; si no está, una estimación que cuenta de más, nunca
/// de menos—.
Future<int> countGemmaTokens(InferenceChat chat, String text) =>
    chat.session.sizeInTokens(text);

/// La sesión de una charla sobre `flutter_gemma`, que se mantiene abierta
/// entre mensajes —el modelo ve todo lo dicho antes— y retiene el modelo
/// mientras esté en uso (F27, `LanguageModelGate.holdForUser`).
///
/// **La respuesta llega de a pedazos** (F30, [send]): la pantalla la muestra
/// mientras el modelo la escribe, y la puede cortar.
///
/// **Nunca se pasa de la ventana** (F30). El modelo lee, como mucho,
/// [window] tokens de una vez: la instrucción, todo lo conversado en la
/// sesión, el mensaje nuevo y la respuesta. Antes de mandar cada mensaje se
/// cuenta —con el tokenizador del modelo— si entra junto con lo ya
/// conversado y la respuesta más larga posible ([replyTokens]). Si no entra,
/// la sesión se cierra y se abre una nueva que recibe, junto con el mensaje,
/// lo conversado hasta ahí: los últimos intercambios que entren en lo que
/// queda de la ventana. Hasta F30, en el chat con la bóveda —cada mensaje
/// lleva sus fuentes— la ventana se llenaba a los dos o tres mensajes. El
/// recorte automático de `flutter_gemma` no sirve para esto: solo cuenta lo
/// que escribe el modelo, no lo que se le manda, así que nunca se activa.
///
/// Si pasa un rato sin uso y sin la pantalla a la vista, la sesión se cierra
/// y el modelo pasa a la cola de la IA. El próximo mensaje la reabre igual,
/// con lo conversado: un solo mensaje de la persona, porque así lo entienden
/// todos los formatos de `flutter_gemma` —un turno del modelo agregado a mano
/// no lo leen igual un `.task` y un `.litertlm`—.
class GemmaChatSession {
  GemmaChatSession(
    this._gate,
    this._open, {
    required Stream<String> Function(InferenceChat chat) reply,
    required String Function(InferenceChat chat, String text) clean,
    required this.instruction,
    required this.window,
    required this.replyTokens,
    required Future<void> Function() prepareImages,
    required int Function() loadCount,
    GemmaTokenCounter countTokens = countGemmaTokens,
  }) : _reply = reply,
       _clean = clean,
       _prepareImages = prepareImages,
       _loadCount = loadCount,
       _count = countTokens {
    _hold = _gate.holdForUser(onIdle: _closeForIdle);
  }

  final LanguageModelGate _gate;

  /// Abre una sesión nueva con la instrucción de la charla. Corre dentro del
  /// turno de la persona: no lo pide.
  final Future<InferenceChat> Function() _open;

  /// La respuesta de la sesión al mensaje que ya tiene cargado, de a
  /// pedazos y medida (`measuredReply`, F30).
  final Stream<String> Function(InferenceChat chat) _reply;

  /// El texto final de una respuesta (`cleanReply`).
  final String Function(InferenceChat chat, String text) _clean;

  final GemmaTokenCounter _count;

  /// Deja el modelo listo para mirar fotos (`GemmaEngine.model(vision:
  /// true)`): puede volver a cargarlo, y entonces la sesión abierta muere
  /// con el modelo de antes.
  final Future<void> Function() _prepareImages;

  /// Cuántas veces se cargó el modelo (`GemmaEngine.loadCount`): si cambió
  /// desde que se abrió la sesión, la sesión ya no sirve.
  final int Function() _loadCount;

  /// [_loadCount] al abrir la sesión.
  var _openedOnLoad = 0;

  /// La instrucción con la que se abre cada sesión: ocupa ventana.
  final String instruction;

  /// La ventana del modelo, en tokens.
  final int window;

  /// El tope de una respuesta (`maxOutputTokens` de la sesión).
  final int replyTokens;

  late final LanguageModelHold _hold;
  InferenceChat? _chat;

  /// Cuántos tokens de la ventana lleva usados la sesión abierta.
  var _used = 0;

  /// Cuántos ocupa la instrucción, que ocupa cualquier sesión.
  var _instructionTokens = 0;

  /// Si la sesión se cerró por falta de uso: el próximo mensaje lleva lo
  /// conversado.
  var _resuming = false;

  var _closed = false;

  /// La sesión que está escribiendo una respuesta ahora, para cortarla.
  InferenceChat? _writing;

  /// Lo que se dijo, de a intercambios: lo que escribió la persona —sin el
  /// contexto de la bóveda, que se busca de nuevo— y lo que contestó el
  /// modelo.
  final _turns = <({String said, String answer})>[];

  /// Lo que se reserva en la ventana para cada mensaje, además del mensaje:
  /// la respuesta más larga, las marcas del turno y el margen.
  int get _reserve => replyTokens + kTurnTemplateTokens + kWindowSafetyTokens;

  /// Abre la primera sesión. Si falla, suelta el modelo.
  Future<void> openFirst() async {
    try {
      await _gate.runForUser(_openFresh);
    } on Object {
      _hold.release();
      rethrow;
    }
  }

  /// Manda [prompt] —lo que [said] la persona, con lo que lo acompañe— y da
  /// la respuesta a medida que se escribe ([ChatReplyStream]). Cuenta como
  /// uso al mandarlo y al terminar.
  ChatReplyStream send({
    required String prompt,
    required String said,
    List<Uint8List> images = const [],
  }) {
    late final StreamController<String> out;
    var stopped = false;
    out = StreamController<String>(
      onListen: () => unawaited(
        _write(
          prompt: prompt,
          said: said,
          images: images,
          out: out,
          stopped: () => stopped,
        ),
      ),
      onCancel: () async {
        stopped = true;
        // Corta lo que se esté escribiendo; si todavía espera su turno, no
        // llega a mandarse.
        await _writing?.stopGeneration();
      },
    );
    return out.stream;
  }

  Future<void> _write({
    required String prompt,
    required String said,
    required List<Uint8List> images,
    required StreamController<String> out,
    required bool Function() stopped,
  }) async {
    _hold.touch();
    var last = '';
    void give(String text) {
      if (stopped() || text == last) return;
      last = text;
      out.add(text);
    }

    try {
      final answer = await _gate.runForUser(() async {
        if (stopped() || _closed) return null;
        final chat = await _load(prompt, images);
        _writing = chat;
        try {
          final before = chat.currentTokens;
          final text = StringBuffer();
          // Se lee hasta el final aunque la corten: `flutter_gemma` anota la
          // respuesta en la sesión al terminar, y cortarla con
          // `stopGeneration` la termina limpia con lo escrito.
          await for (final piece in _reply(chat)) {
            text.write(piece);
            give(text.toString().trimLeft());
          }
          final answer = _clean(chat, text.toString());
          final generated = chat.currentTokens - before;
          _used +=
              kTurnTemplateTokens +
              (generated > 0 ? generated : await _count(chat, answer));
          return answer;
        } finally {
          _writing = null;
        }
      });
      if (answer != null) {
        // La respuesta entera y limpia, si difiere de lo último que se dio.
        give(answer);
        _turns.add((
          said: images.isEmpty ? said : '$said [con ${images.length} foto(s)]',
          answer: answer,
        ));
      }
      // El motor es de terceros y falla de formas sin un tipo propio: el
      // error va a quien escucha la respuesta, que es quien sabe mostrarlo.
    } on Object catch (error, stackTrace) {
      if (!stopped()) out.addError(error, stackTrace);
    } finally {
      _hold.touch();
      await out.close();
    }
  }

  /// La sesión con el mensaje ya cargado, lista para responder. Si el
  /// mensaje no entra en la ventana junto con lo ya conversado, abre una
  /// sesión nueva y le da lo conversado que entre. Si no entraría ni solo,
  /// falla sin tocar la sesión.
  Future<InferenceChat> _load(String prompt, List<Uint8List> images) async {
    if (images.isNotEmpty) await _prepareImages();
    if (_chat != null && _openedOnLoad != _loadCount()) {
      // El modelo se volvió a cargar —para mirar fotos, o porque se soltó—
      // y la sesión se cerró con el de antes: sigue una nueva, con lo
      // conversado.
      _chat = null;
      _resuming = true;
    }
    final open = _chat;
    int? needed;
    if (open != null) {
      needed = await _needed(open, prompt, images);
      if (!_resuming && _used + needed + _reserve <= window) {
        await _add(open, prompt, images);
        _used += needed;
        return open;
      }
      if (_instructionTokens + needed + _reserve > window) {
        throw const ChatMessageTooLongException();
      }
      // No entra: lo conversado pasa a una sesión nueva.
      _chat = null;
      await open.close();
    }

    final chat = await _openFresh();
    needed ??= await _needed(chat, prompt, images);
    final room = window - _used - needed - _reserve;
    if (room < 0) {
      // La sesión nueva quedó vacía: el próximo mensaje la vuelve a abrir
      // con lo conversado.
      _resuming = true;
      throw const ChatMessageTooLongException();
    }
    _resuming = false;
    final text = await _withTranscript(chat, prompt, room);
    await _add(chat, text, images);
    _used += identical(text, prompt)
        ? needed
        : await _needed(chat, text, images);
    return chat;
  }

  /// Lo que ocupa en la ventana un mensaje con [text] y [images].
  Future<int> _needed(
    InferenceChat chat,
    String text,
    List<Uint8List> images,
  ) async => await _count(chat, text) + images.length * kImageTokens;

  Future<void> _add(InferenceChat chat, String text, List<Uint8List> images) =>
      chat.addQueryChunk(
        images.isEmpty
            ? Message.text(text: text, isUser: true)
            : Message.withImages(text: text, imageBytes: images, isUser: true),
      );

  /// Abre una sesión nueva y vacía: solo la instrucción ocupa la ventana.
  Future<InferenceChat> _openFresh() async {
    final chat = await _open();
    _chat = chat;
    _openedOnLoad = _loadCount();
    _used = _instructionTokens = await _count(chat, instruction);
    return chat;
  }

  /// Termina la charla: corta lo que se esté escribiendo y cierra la sesión
  /// en un turno de la persona —nada usa el modelo mientras tanto—.
  Future<void> close() async {
    _closed = true;
    await _writing?.stopGeneration();
    try {
      await _gate.runForUser(() async {
        final chat = _chat;
        _chat = null;
        await chat?.close();
      }, preempt: false);
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
  /// entren en [room] tokens; si ni el último entra, su final.
  Future<String> _withTranscript(
    InferenceChat chat,
    String prompt,
    int room,
  ) async {
    if (_turns.isEmpty) return prompt;
    const header = 'Lo que veníamos conversando:\n\n';
    const separator = '\n\n---\n\n';
    var left = room - await _count(chat, header + separator);
    final lines = <String>[];
    for (final turn in _turns.reversed) {
      final line = 'Persona: ${turn.said}\nAsistente: ${turn.answer}';
      final tokens = await _count(chat, '$line\n\n');
      if (tokens <= left) {
        lines.insert(0, line);
        left -= tokens;
        continue;
      }
      if (lines.isEmpty) {
        final tail = await _tailThatFits(chat, line, left);
        if (tail.isNotEmpty) lines.add(tail);
      }
      break;
    }
    if (lines.isEmpty) return prompt;
    return '$header${lines.join('\n\n')}$separator$prompt';
  }

  /// El final de [line] que entra en [room] tokens: se prueba con dos
  /// caracteres por token —un token casi nunca es más corto— y se acorta a la
  /// mitad hasta que entre.
  Future<String> _tailThatFits(
    InferenceChat chat,
    String line,
    int room,
  ) async {
    if (room <= 0) return '';
    var chars = (room * 2).clamp(0, line.length);
    while (chars > 0) {
      final tail = line.substring(line.length - chars);
      if (await _count(chat, tail) <= room) return tail;
      chars ~/= 2;
    }
    return '';
  }
}
