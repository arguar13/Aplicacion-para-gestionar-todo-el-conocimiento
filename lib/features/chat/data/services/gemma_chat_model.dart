import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:sinapsis/core/domain/entities/chat_source.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcard_draft_parser.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcard_generator.dart';

/// Le pide instrucciones tajantes de no inventar nada que no esté en el
/// contexto: es lo único que separa una respuesta útil de una que suena
/// bien pero mezcla lo que dice la bóveda con lo que el modelo "sabe" de
/// su entrenamiento —que acá no tiene ningún valor, porque nadie puede
/// verificarlo contra nada—.
const _systemInstruction =
    'Respondé siempre en español, de forma breve y directa. Basate '
    'ÚNICAMENTE en el contexto que se te da a continuación: nunca agregues '
    'información de tu propio conocimiento. Si el contexto no alcanza para '
    'responder la pregunta, decilo con claridad en vez de inventar algo. '
    'Cuando uses un dato de una fuente, mencioná su número entre corchetes, '
    'como [1] o [2].';

/// Mismo criterio que el de arriba, pero para generar tarjetas en vez de
/// contestar una pregunta: sin citas ni corchetes, con el formato exacto
/// que `parseFlashcardDrafts` sabe leer.
const _flashcardSystemInstruction =
    'Respondé siempre en español. Tu única tarea es generar preguntas de '
    'estudio con su respuesta a partir del contenido que se te da, '
    'basándote ÚNICAMENTE en ese contenido. Usá EXACTAMENTE este formato, '
    'una pregunta y una respuesta por vez, sin numerar, sin usar Markdown '
    'ni comillas:\nP: <pregunta>\nR: <respuesta>';

/// [ChatModel] sobre `flutter_gemma`: Gemma corriendo en el dispositivo, vía
/// FFI directo —sin JVM, sin servidor propio, ver la decisión 20 en
/// docs/arquitectura.md—.
///
/// El modelo cargado se guarda en memoria entre preguntas: son varios
/// cientos de megas de pesos, y volver a cargarlos en cada pregunta sería
/// pagar ese costo de nuevo por cada intercambio. Lo que sí se abre y se
/// cierra por pregunta es la sesión de chat —barata, comparada con el
/// modelo—, para que una pregunta no arrastre el historial de la anterior:
/// cada pregunta recupera sus propias fuentes y no tiene por qué compartir
/// contexto con la charla previa.
///
/// También implementa [FlashcardGenerator]: generar tarjetas es otra tarea
/// del mismo modelo ya cargado, no un motor aparte. Que la clase concreta
/// viva en el feature `chat` y no en `flashcards` es una asimetría real
/// —`flashcards` depende de una implementación de `chat`—, aceptada acá
/// porque la alternativa (mover la lógica de cachear el modelo a un tercer
/// lugar compartido) es más superficie nueva por una sola clase que la
/// usa.
class GemmaChatModel implements ChatModel, FlashcardGenerator {
  GemmaChatModel();

  InferenceModel? _model;

  Future<InferenceModel> _activeModel() async {
    final cached = _model;
    if (cached != null) return cached;

    if (!FlutterGemma.hasActiveModel()) {
      throw const ChatModelNotReadyException();
    }

    final model = await FlutterGemma.getActiveModel(maxTokens: 2048);
    _model = model;
    return model;
  }

  @override
  Future<String> answer({
    required String question,
    required List<ChatSource> sources,
  }) async {
    final model = await _activeModel();
    final chat = await model.createChat(systemInstruction: _systemInstruction);

    try {
      await chat.addQueryChunk(
        Message.text(text: _prompt(question, sources), isUser: true),
      );
      final response = await chat.generateChatResponse();

      return switch (response) {
        TextResponse(:final token) => token,
        // Un vínculo o pensamiento sin texto: no debería pasar sin
        // herramientas configuradas, pero una cadena vacía es una
        // respuesta honesta —"no contestó nada"— antes que un `null` que
        // obligaría a la pantalla a inventar un mensaje de error para algo
        // que no fue un error.
        _ => '',
      };
    } finally {
      await chat.close();
    }
  }

  String _prompt(String question, List<ChatSource> sources) {
    final context = [
      for (var i = 0; i < sources.length; i++)
        '[${i + 1}] ${sources[i].itemTitle}\n${sources[i].excerpt}',
    ].join('\n\n');

    return 'Contexto:\n$context\n\nPregunta: $question';
  }

  @override
  Future<List<FlashcardDraft>> generate({
    required String content,
    int count = 5,
  }) async {
    final model = await _activeModel();
    final chat = await model.createChat(
      systemInstruction: _flashcardSystemInstruction,
    );

    try {
      await chat.addQueryChunk(
        Message.text(
          text:
              'Generá hasta $count tarjetas a partir de este contenido:\n\n'
              '$content',
          isUser: true,
        ),
      );
      final response = await chat.generateChatResponse();

      final text = switch (response) {
        TextResponse(:final token) => token,
        _ => '',
      };

      return parseFlashcardDrafts(text).take(count).toList();
    } finally {
      await chat.close();
    }
  }
}
