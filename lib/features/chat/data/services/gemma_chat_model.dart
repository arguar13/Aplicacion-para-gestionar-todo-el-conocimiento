import 'dart:typed_data';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:sinapsis/core/domain/entities/chat_source.dart';
import 'package:sinapsis/features/ai_organize/domain/services/map_note_intro.dart';
import 'package:sinapsis/features/ai_organize/domain/services/space_chooser.dart';
import 'package:sinapsis/features/ai_organize/domain/services/topic_parent_chooser.dart';
import 'package:sinapsis/features/ai_organize/domain/services/vocabulary_budget.dart';
import 'package:sinapsis/features/chat/data/services/gemma_chat_session.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_gate.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcard_draft_parser.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcard_generator.dart';
import 'package:sinapsis/features/flashcards/domain/services/quiz_question_generator.dart';
import 'package:sinapsis/features/graph/domain/services/relation_suggestion_parser.dart';
import 'package:sinapsis/features/graph/domain/services/relation_suggestion_service.dart';
import 'package:sinapsis/features/library/domain/services/summarization_service.dart';
import 'package:sinapsis/features/notes/domain/services/derived_claim_anchor.dart';
import 'package:sinapsis/features/notes/domain/services/derived_note_generator.dart';
import 'package:sinapsis/features/notes/domain/services/derived_note_response_parser.dart';
import 'package:sinapsis/features/suggestions/domain/services/property_suggestion_parser.dart';
import 'package:sinapsis/features/suggestions/domain/services/property_suggestion_service.dart';

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

/// Mismo formato que `_flashcardSystemInstruction` —reusa
/// `parseFlashcardDrafts`, F20: una pregunta de opción múltiple con su
/// respuesta correcta es la misma forma que una tarjeta—, pero pidiendo
/// preguntas de opción múltiple en vez de estudio libre. Las opciones
/// incorrectas NUNCA se piden acá: salen de material real de la bóveda, no
/// de lo que el modelo inventaría como distractor.
const _quizQuestionSystemInstruction =
    'Respondé siempre en español. Tu única tarea es generar preguntas de '
    'opción múltiple con su respuesta correcta a partir del contenido que '
    'se te da, basándote ÚNICAMENTE en ese contenido. NO propongas '
    'opciones incorrectas: eso lo hace otra parte del sistema. Usá '
    'EXACTAMENTE este formato, una pregunta y su respuesta correcta por '
    'vez, sin numerar, sin usar Markdown ni comillas:\nP: <pregunta>\n'
    'R: <la respuesta correcta>\nC: <la frase del contenido de la que sale '
    'la respuesta, copiada TEXTUALMENTE, sin cambiar ni una palabra>';

/// Mismo criterio que el de arriba, pero para generar tarjetas en vez de
/// contestar una pregunta: sin citas ni corchetes, con el formato exacto
/// que `parseFlashcardDrafts` sabe leer.
const _flashcardSystemInstruction =
    'Respondé siempre en español. Tu única tarea es generar preguntas de '
    'estudio con su respuesta a partir del contenido que se te da, '
    'basándote ÚNICAMENTE en ese contenido. Usá EXACTAMENTE este formato, '
    'una pregunta y una respuesta por vez, sin numerar, sin usar Markdown '
    'ni comillas:\nP: <pregunta>\nR: <respuesta>\nC: <la frase del '
    'contenido de la que sale la respuesta, copiada TEXTUALMENTE, sin '
    'cambiar ni una palabra>';

/// Mismo criterio que `_flashcardSystemInstruction`, para juzgar vínculos en
/// vez de generar tarjetas: un formato exacto y estricto, para que un
/// modelo chico se desvíe lo menos posible de él.
const _relationSuggestionSystemInstruction =
    'Respondé siempre en español. Tu única tarea es identificar qué '
    'elementos de una lista numerada están relacionados con un elemento '
    'semilla, basándote ÚNICAMENTE en los títulos y fragmentos que se te '
    'dan. Para cada elemento relacionado, respondé UNA línea con este '
    'formato exacto, sin Markdown ni numeración propia:\n'
    'SUGERENCIA: <número> | <clave> | <certeza> | <motivo breve>\n'
    'donde <número> es el número de la lista, <clave> es exactamente una '
    'de estas palabras: relacionado, continua, contradice, cita, resume, y '
    '<certeza> es alta si los fragmentos muestran el vínculo con claridad o '
    'media si es probable pero no seguro. '
    'Si ningún elemento está relacionado, no respondas ninguna línea '
    'SUGERENCIA. No respondas nada más aparte de esas líneas.';

/// Mismo criterio que `_relationSuggestionSystemInstruction`, para juzgar
/// propiedades en vez de vínculos: pide usar SOLO una categoría de la lista
/// dada —nunca inventar una nueva, ver decisión D2 de F4—, preferir un valor
/// ya existente bajo esa categoría y proponer uno nuevo solo si ninguno
/// corresponde.
const _propertySuggestionSystemInstruction =
    'Respondé siempre en español. Tu única tarea es identificar qué '
    'propiedades del elemento corresponden, basándote ÚNICAMENTE en las '
    'categorías existentes que se te dan y en el contenido del elemento. '
    'Para cada categoría a la que le encuentres un valor, respondé UNA '
    'línea con este formato exacto, sin Markdown ni numeración:\n'
    'PROPIEDAD: <categoría> | <valor>\n'
    'Usá SIEMPRE una de las categorías de la lista dada, nunca inventes una '
    'categoría nueva. Preferí un valor ya existente bajo esa categoría; '
    'proponé uno nuevo solo si ninguno de los existentes corresponde. Si '
    'ninguna categoría aplica, no respondas ninguna línea PROPIEDAD. No '
    'respondas nada más aparte de esas líneas.';

/// A diferencia de `_systemInstruction`, sin ninguna restricción al
/// contenido de la bóveda: acá el pedido es justamente lo contrario, hablar
/// con el modelo como con cualquier asistente de lenguaje general.
const _freeConversationSystemInstruction =
    'Sos un asistente conversacional útil y directo. Respondé siempre en '
    'español, salvo que te pidan otro idioma explícitamente.';

/// La del modo "con mi bóveda", pero conversacional: a diferencia de
/// `_systemInstruction` —una pregunta, cita o silencio—, acá se pide
/// charlar de verdad. Sigue citando cuando hay de dónde, pero no se niega a
/// responder ante lo que no es estrictamente una pregunta puntual: "hacé un
/// resumen", "y qué más dice sobre eso", "compará estas dos cosas" son
/// pedidos legítimos sobre el mismo contenido, no algo para lo que haya que
/// inventar una excusa.
const _vaultConversationSystemInstruction =
    'Sos un asistente que ayuda a explorar y conversar sobre el contenido '
    'de la bóveda del usuario. Respondé siempre en español, de forma '
    'natural, como en cualquier chat — no solo con citas sueltas. Podés '
    'resumir, comparar, elaborar o responder preguntas generales sobre el '
    'contenido, no solo repetirlo. Cuando se te da contexto de la bóveda, '
    'usalo como base de tu respuesta y mencioná el número de la fuente '
    'entre corchetes, como [1] o [2], cuando cites un dato puntual. Si no '
    'hay contexto relevante para lo que preguntan, decilo con honestidad, '
    'pero seguí la conversación con naturalidad en vez de negarte a '
    'contestar.';

/// Mismo criterio que `_relationSuggestionSystemInstruction` (F27): elegir
/// en una lista numerada, con la certeza, en una sola línea de formato
/// exacto, y nunca inventar un tema nuevo —los temas los arma la persona—.
const _spaceChoiceSystemInstruction =
    'Respondé siempre en español. Tu única tarea es elegir en cuál de los '
    'temas de una lista numerada va un elemento, basándote ÚNICAMENTE en su '
    'título y su fragmento. Respondé UNA sola línea con este formato exacto, '
    'sin Markdown:\nTEMA: <número> | <certeza>\ndonde <número> es el número '
    'del tema elegido y <certeza> es alta si el elemento claramente es de '
    'ese tema o media si es probable pero no seguro. Si no va en ninguno, '
    'respondé exactamente: TEMA: ninguno. Nunca inventes un tema que no esté '
    'en la lista. No respondas nada más.';

/// Mismo criterio que `_spaceChoiceSystemInstruction` (F27, el Atlas): elegir
/// en una lista numerada, con la certeza, sin inventar un tema. «Alta» es que
/// el tema es claramente una parte o un caso del elegido —«Roma» de «Historia
/// antigua»—, no solo que se parecen.
const _topicParentSystemInstruction =
    'Respondé siempre en español. Tu única tarea es elegir bajo cuál de los '
    'temas de una lista numerada va otro tema, como un subtema dentro de un '
    'árbol, basándote ÚNICAMENTE en los nombres de los temas y en el título '
    'del elemento donde aparece. Respondé UNA sola línea con este formato '
    'exacto, sin Markdown:\nPADRE: <número> | <certeza>\ndonde <número> es '
    'el número del tema elegido y <certeza> es alta si el tema claramente es '
    'una parte o un caso del elegido, o media si es probable pero no seguro. '
    'Si no va bajo ninguno, respondé exactamente: PADRE: ninguno. Nunca '
    'inventes un tema que no esté en la lista. No respondas nada más.';

/// La introducción de una nota mapa (F27, el Atlas): lo mismo que
/// `_summarizationSystemInstruction` —nada que no esté en lo que se le da,
/// texto corrido— pero sobre títulos y fragmentos, y sin corchetes: los
/// enlaces de la nota los arma la app, nunca el modelo.
const _mapIntroSystemInstruction =
    'Respondé siempre en español. Tu única tarea es escribir una '
    'introducción breve, de dos o tres oraciones, para el índice de un tema, '
    'basándote ÚNICAMENTE en los títulos y fragmentos de los elementos que se '
    'te dan: nunca agregues datos, fechas, nombres ni afirmaciones que no '
    'estén ahí. Decí de qué trata el material reunido, sin enumerar los '
    'elementos uno por uno. Texto corrido, sin viñetas, sin títulos, sin '
    'Markdown y sin corchetes.';

/// Mismo criterio que el resto de las instrucciones de sistema: nada de
/// agregar datos que no estén en el contenido, y una redacción corrida —sin
/// viñetas ni encabezados— porque lo que sigue casi siempre se escucha en
/// voz alta con el lector de la app, y una lista con viñetas se lee como
/// "guion, guion, guion" en lugar de una idea seguida.
const _summarizationSystemInstruction =
    'Respondé siempre en español. Tu única tarea es resumir el contenido '
    'que se te da, basándote ÚNICAMENTE en ese contenido: nunca agregues '
    'información de tu propio conocimiento. El resumen va en dos o tres '
    'párrafos cortos de texto corrido, sin viñetas, sin encabezados y sin '
    'Markdown.';

/// El formato de respuesta compartido por los cuatro derivados (D5): lo
/// único que cambia entre `_studyGuideSystemInstruction` y las otras tres es
/// QUÉ generar, nunca el formato en que se lo pide —mismo criterio que
/// `_flashcardSystemInstruction`, un formato simple y único le deja al
/// modelo menos formas de desviarse—. `C:` es obligatoria y textual: sin
/// ella, `anchorDerivedClaims` descarta la afirmación entera (D6).
const _derivedFormatInstruction =
    'Usá EXACTAMENTE este formato, sin Markdown ni numeración propia. Para '
    'agrupar afirmaciones bajo un título (opcional):\nT: <título>\nLuego, '
    'por cada afirmación:\nA: <afirmación>\nC: <la frase de las fuentes de '
    'la que sale, copiada TEXTUALMENTE, sin cambiar ni una palabra>\nLa '
    'línea C: es obligatoria en cada afirmación: sin ella se descarta.';

const _studyGuideSystemInstruction =
    'Respondé siempre en español. Tu única tarea es armar una guía de '
    'estudio a partir del contenido de las fuentes que se te dan, '
    'basándote ÚNICAMENTE en ellas. Agrupá las afirmaciones clave por '
    'tema, con un título por grupo. $_derivedFormatInstruction';

const _openQuestionsSystemInstruction =
    'Respondé siempre en español. Tu única tarea es proponer preguntas '
    'abiertas que el contenido de las fuentes permite responder, '
    'basándote ÚNICAMENTE en ellas: cada "afirmación" es en realidad una '
    'pregunta de repaso. No hace falta agrupar por título. '
    '$_derivedFormatInstruction';

const _outlineSystemInstruction =
    'Respondé siempre en español. Tu única tarea es armar un esquema con '
    'los puntos principales del contenido de las fuentes que se te dan, '
    'basándote ÚNICAMENTE en ellas. Agrupá los puntos por tema, con un '
    'título por grupo. $_derivedFormatInstruction';

const _timelineSystemInstruction =
    'Respondé siempre en español. Tu única tarea es armar una cronología '
    'con los hechos fechables del contenido de las fuentes que se te dan, '
    'basándote ÚNICAMENTE en ellas, en el orden en que ocurrieron: cada '
    '"afirmación" es un hecho, con su fecha si la tiene. No hace falta '
    'agrupar por título. $_derivedFormatInstruction';

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
/// También implementa [FlashcardGenerator], [RelationSuggestionService],
/// [SummarizationService], [PropertySuggestionService] y
/// [DerivedNoteGenerator]: generar tarjetas, sugerir vínculos, resumir,
/// sugerir propiedades y armar derivados son otras tareas del mismo modelo
/// ya cargado, no motores aparte. Que la clase concreta viva en el feature
/// `chat` y no en `flashcards`, `graph`, `suggestions` o `notes` es una
/// asimetría real —esos dependen de una implementación de `chat`—, aceptada
/// acá porque la alternativa (mover la lógica de cachear el modelo a un
/// tercer lugar compartido) es más superficie nueva por unas pocas clases
/// que la usan.
class GemmaChatModel
    implements
        ChatModel,
        FlashcardGenerator,
        RelationSuggestionService,
        SummarizationService,
        PropertySuggestionService,
        DerivedNoteGenerator,
        QuizQuestionGenerator {
  /// Cada uso pasa por [gate] (F27): esta instancia es la de la persona —el
  /// chat, resumir, las tarjetas y el quiz a mano— y [background], la de la
  /// cola de la IA.
  ///
  /// [ensureReady] es `ChatModelManager.isReady` del modelo elegido: antes
  /// de cargarlo por primera vez en la sesión, lo registra si su archivo
  /// está entero —`flutter_gemma` no lo recuerda al reabrir la app; ver
  /// `GemmaChatModelManager.isReady`—. Sin esto, quien usara el modelo sin
  /// haber preguntado antes encontraba «no está descargado» con el archivo
  /// ahí.
  GemmaChatModel({
    required LanguageModelGate gate,
    required Future<bool> Function() ensureReady,
  }) : this._(gate, _LoadedGemma(ensureReady), inBackground: false);

  GemmaChatModel._(this._gate, this._loaded, {required bool inBackground})
    : _inBackground = inBackground;

  final LanguageModelGate _gate;

  /// El modelo cargado, compartido con [background]: son los mismos pesos.
  final _LoadedGemma _loaded;

  final bool _inBackground;

  /// El mismo modelo ya cargado, pero con el turno de la cola de la IA (F27):
  /// espera a que la persona no lo esté usando y le cede el paso. Es lo que
  /// reciben los pasos de la IA que organiza sola; nunca la interfaz.
  late final GemmaChatModel background = _inBackground
      ? this
      : GemmaChatModel._(_gate, _loaded, inBackground: true);

  /// Corre [work] con el modelo cargado, en el turno que le toca a esta
  /// instancia. Todo método que abre una sesión pasa por acá: dos sesiones a
  /// la vez se pisan la única que tiene `flutter_gemma` (ver
  /// `LanguageModelGate`).
  Future<T> _withTurn<T>(Future<T> Function(InferenceModel model) work) {
    Future<T> run() async => work(await _activeModel());
    return _inBackground ? _gate.runInBackground(run) : _gate.runForUser(run);
  }

  Future<InferenceModel> _activeModel() async {
    final cached = _loaded.model;
    if (cached != null) return cached;

    if (!await _loaded.ensureReady()) {
      throw const ChatModelNotReadyException();
    }

    final model = await FlutterGemma.getActiveModel(maxTokens: 2048);
    _loaded.model = model;
    return model;
  }

  @override
  Future<String> answer({
    required String question,
    required List<ChatSource> sources,
  }) {
    return _withTurn((model) async {
      final chat = await model.createChat(
        systemInstruction: _systemInstruction,
      );

      try {
        await chat.addQueryChunk(
          Message.text(
            text: _buildVaultPrompt(question, sources),
            isUser: true,
          ),
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
    });
  }

  @override
  Future<FreeConversation> startConversation() async => _GemmaFreeConversation(
    await _openConversation(_freeConversationSystemInstruction),
  );

  @override
  Future<VaultConversation> startVaultConversation() async =>
      _GemmaVaultConversation(
        await _openConversation(_vaultConversationSystemInstruction),
      );

  /// Abre una charla que deja su sesión abierta entre mensajes. Desde antes de
  /// abrirla, y mientras esté en uso, la cola de la IA no usa el modelo
  /// (F27): le cerraría la sesión a la charla. Si abrirla falla, el modelo se
  /// suelta.
  Future<GemmaChatSession> _openConversation(String systemInstruction) async {
    final session = GemmaChatSession(
      _gate,
      () async => (await _activeModel()).createChat(
        systemInstruction: systemInstruction,
      ),
    );
    await session.openFirst();
    return session;
  }

  @override
  Future<List<FlashcardDraft>> generate({
    required String content,
    int count = 5,
  }) {
    return _withTurn((model) async {
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
    });
  }

  @override
  Future<List<FlashcardDraft>> generateQuizQuestions({
    required String content,
    int count = 5,
  }) {
    return _withTurn((model) async {
      final chat = await model.createChat(
        systemInstruction: _quizQuestionSystemInstruction,
      );

      try {
        await chat.addQueryChunk(
          Message.text(
            text:
                'Generá hasta $count preguntas de opción múltiple a partir '
                'de este contenido:\n\n$content',
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
    });
  }

  @override
  Future<String> summarize({required String content}) {
    return _withTurn((model) async {
      final chat = await model.createChat(
        systemInstruction: _summarizationSystemInstruction,
      );

      try {
        await chat.addQueryChunk(Message.text(text: content, isUser: true));
        final response = await chat.generateChatResponse();

        return switch (response) {
          TextResponse(:final token) => token,
          _ => '',
        };
      } finally {
        await chat.close();
      }
    });
  }

  @override
  Future<List<RelationSuggestion>> suggestRelations({
    required String seedTitle,
    required String seedExcerpt,
    required List<RelationCandidate> candidates,
  }) async {
    if (candidates.isEmpty) return const [];

    return _withTurn((model) async {
      final chat = await model.createChat(
        systemInstruction: _relationSuggestionSystemInstruction,
      );

      try {
        final list = [
          for (var i = 0; i < candidates.length; i++)
            '${i + 1}. ${candidates[i].title}\n${candidates[i].excerpt}',
        ].join('\n\n');

        await chat.addQueryChunk(
          Message.text(
            text:
                'Elemento semilla: $seedTitle\n$seedExcerpt\n\n'
                'Lista de candidatos:\n$list',
            isUser: true,
          ),
        );
        final response = await chat.generateChatResponse();

        final text = switch (response) {
          TextResponse(:final token) => token,
          _ => '',
        };

        final suggestions = <RelationSuggestion>[];
        for (final line in parseRelationSuggestions(text)) {
          if (line.candidateIndex < 0 ||
              line.candidateIndex >= candidates.length) {
            continue;
          }
          suggestions.add(
            RelationSuggestion(
              itemId: candidates[line.candidateIndex].itemId,
              kind: line.kind,
              reason: line.reason,
              certainty: line.certainty,
            ),
          );
        }
        return suggestions;
      } finally {
        await chat.close();
      }
    });
  }

  @override
  Future<List<PropertyDraft>> suggestProperties({
    required String itemTitle,
    required String itemContent,
    required List<PropertyVocabularyCategory> categories,
  }) async {
    if (categories.isEmpty) return const [];

    return _withTurn((model) async {
      final chat = await model.createChat(
        systemInstruction: _propertySuggestionSystemInstruction,
      );

      try {
        final list = [
          // La misma forma con que se midió lo que ocupa (F27).
          for (final category in categories)
            describeVocabularyCategory(category),
        ].join('\n');

        await chat.addQueryChunk(
          Message.text(
            text:
                'Categorías existentes:\n$list\n\n'
                'Elemento: $itemTitle\n$itemContent',
            isUser: true,
          ),
        );
        final response = await chat.generateChatResponse();

        final text = switch (response) {
          TextResponse(:final token) => token,
          _ => '',
        };

        final knownCategories = categories.map((c) => c.name).toList();
        final drafts = <PropertyDraft>[];
        for (final line in parsePropertySuggestions(
          text,
          knownCategories: knownCategories,
        )) {
          final category = categories.firstWhere(
            (c) => c.name == line.category,
          );
          drafts.add(
            PropertyDraft(
              definitionId: category.definitionId,
              definitionName: category.name,
              value: line.value,
            ),
          );
        }
        return drafts;
      } finally {
        await chat.close();
      }
    });
  }

  /// Un `SpaceChooser` (F27): en cuál de [spaces] va el elemento.
  Future<SpaceChoice?> chooseSpace({
    required String itemTitle,
    required String excerpt,
    required List<String> spaces,
  }) {
    if (spaces.isEmpty) return Future.value();

    return _withTurn((model) async {
      final chat = await model.createChat(
        systemInstruction: _spaceChoiceSystemInstruction,
      );

      try {
        final list = [
          for (var i = 0; i < spaces.length; i++) '${i + 1}. ${spaces[i]}',
        ].join('\n');

        await chat.addQueryChunk(
          Message.text(
            text: 'Temas:\n$list\n\nElemento: $itemTitle\n$excerpt',
            isUser: true,
          ),
        );
        final response = await chat.generateChatResponse();

        final text = switch (response) {
          TextResponse(:final token) => token,
          _ => '',
        };
        return parseSpaceChoice(text, spaceCount: spaces.length);
      } finally {
        await chat.close();
      }
    });
  }

  /// Un `TopicParentChooser` (F27, el Atlas): bajo cuál de [candidates] va
  /// [topic].
  Future<TopicParentChoice?> chooseTopicParent({
    required String topic,
    required String itemTitle,
    required List<String> candidates,
  }) {
    if (candidates.isEmpty) return Future.value();

    return _withTurn((model) async {
      final chat = await model.createChat(
        systemInstruction: _topicParentSystemInstruction,
      );

      try {
        final list = [
          for (var i = 0; i < candidates.length; i++)
            '${i + 1}. ${candidates[i]}',
        ].join('\n');

        await chat.addQueryChunk(
          Message.text(
            text:
                'Temas del árbol:\n$list\n\nTema por ubicar: $topic\n'
                'Aparece en: $itemTitle',
            isUser: true,
          ),
        );
        final response = await chat.generateChatResponse();

        final text = switch (response) {
          TextResponse(:final token) => token,
          _ => '',
        };
        return parseTopicParentChoice(text, candidateCount: candidates.length);
      } finally {
        await chat.close();
      }
    });
  }

  /// Un `MapIntroWriter` (F27, el Atlas): la introducción de la nota mapa de
  /// [topic], con un pedido acotado por `buildMapIntroPrompt`.
  Future<String> writeMapIntroduction({
    required String topic,
    required List<MapIntroEntry> entries,
  }) {
    if (entries.isEmpty) return Future.value('');

    return _withTurn((model) async {
      final chat = await model.createChat(
        systemInstruction: _mapIntroSystemInstruction,
      );

      try {
        await chat.addQueryChunk(
          Message.text(
            text: buildMapIntroPrompt(topic: topic, entries: entries),
            isUser: true,
          ),
        );
        final response = await chat.generateChatResponse();

        return switch (response) {
          TextResponse(:final token) => token,
          _ => '',
        };
      } finally {
        await chat.close();
      }
    });
  }

  @override
  Future<DerivedNoteDraft> generateDerivedNote({
    required DerivedNoteType type,
    required List<ChatSource> sources,
  }) async {
    if (sources.isEmpty) {
      return DerivedNoteDraft(type: type, sections: const []);
    }

    return _withTurn((model) async {
      final chat = await model.createChat(
        systemInstruction: _derivedSystemInstructionFor(type),
      );

      try {
        await chat.addQueryChunk(
          Message.text(text: _buildDerivedPrompt(sources), isUser: true),
        );
        final response = await chat.generateChatResponse();

        final text = switch (response) {
          TextResponse(:final token) => token,
          _ => '',
        };

        final raw = parseDerivedNoteResponse(text);
        final sections = anchorDerivedClaims(raw, sources);
        return DerivedNoteDraft(type: type, sections: sections);
      } finally {
        await chat.close();
      }
    });
  }
}

/// [FreeConversation] sobre la sesión de `flutter_gemma`: cada [send]
/// agrega el mensaje y pide una respuesta sin cerrar la sesión, así que el
/// modelo sigue viendo todo lo dicho antes en esta misma conversación —a
/// diferencia de `GemmaChatModel.answer`, que abre y cierra una sesión
/// nueva por pregunta—. Si se cerró por falta de uso, la retoma
/// ([GemmaChatSession]).
class _GemmaFreeConversation implements FreeConversation {
  _GemmaFreeConversation(this._session);

  final GemmaChatSession _session;

  @override
  Future<String> send(String message, {List<Uint8List> images = const []}) =>
      _session.send(prompt: message, said: message, images: images);

  @override
  Future<void> close() => _session.close();
}

/// [VaultConversation] sobre la sesión de `flutter_gemma`: igual que
/// [_GemmaFreeConversation] en que el historial no se cierra entre
/// mensajes, pero cada [send] además le agrega al mensaje del usuario el
/// contexto que trajo `VaultRetriever` para esa vuelta puntual —el mismo
/// formato que ya arma [_buildVaultPrompt]—, así el modelo ve tanto lo
/// conversado antes como lo nuevo que se encontró en la bóveda.
class _GemmaVaultConversation implements VaultConversation {
  _GemmaVaultConversation(this._session);

  final GemmaChatSession _session;

  @override
  Future<String> send({
    required String message,
    required List<ChatSource> sources,
    List<Uint8List> images = const [],
  }) => _session.send(
    prompt: _buildVaultPrompt(message, sources),
    said: message,
    images: images,
  );

  @override
  Future<void> close() => _session.close();
}

/// El mensaje que de verdad se le manda al modelo: la pregunta o el pedido
/// del usuario, más el contexto de la bóveda que se haya encontrado para
/// esa vuelta —numerado, para que citar "[1]" en la respuesta señale
/// exactamente cuál—. Sin fuentes, el contexto queda vacío y el modelo lo
/// ve tal cual: nada que ocultarle sobre lo que sí o no se encontró.
String _buildVaultPrompt(String message, List<ChatSource> sources) {
  if (sources.isEmpty) return message;

  final context = [
    for (var i = 0; i < sources.length; i++)
      '[${i + 1}] ${sources[i].itemTitle}\n${sources[i].excerpt}',
  ].join('\n\n');

  return 'Contexto de la bóveda:\n$context\n\nMensaje: $message';
}

/// Qué generar, según [DerivedNoteType]: el formato de respuesta es siempre
/// el mismo (`_derivedFormatInstruction`), solo cambia esto.
String _derivedSystemInstructionFor(DerivedNoteType type) {
  return switch (type) {
    DerivedNoteType.studyGuide => _studyGuideSystemInstruction,
    DerivedNoteType.openQuestions => _openQuestionsSystemInstruction,
    DerivedNoteType.outline => _outlineSystemInstruction,
    DerivedNoteType.timeline => _timelineSystemInstruction,
  };
}

/// El mensaje que se le manda al modelo para armar un derivado: las fuentes
/// numeradas, mismo formato que [_buildVaultPrompt] —el modelo no necesita
/// citar el número acá, solo copiar la frase textual, pero numerarlas
/// ayuda a que no las mezcle—.
String _buildDerivedPrompt(List<ChatSource> sources) {
  final context = [
    for (var i = 0; i < sources.length; i++)
      '[${i + 1}] ${sources[i].itemTitle}\n${sources[i].excerpt}',
  ].join('\n\n');

  return 'Fuentes:\n$context';
}

/// El modelo de Gemma cargado, compartido entre [GemmaChatModel] y su
/// `background`: los mismos pesos, cargados una sola vez.
class _LoadedGemma {
  _LoadedGemma(this.ensureReady);

  /// Ver el constructor de [GemmaChatModel].
  final Future<bool> Function() ensureReady;

  InferenceModel? model;
}
