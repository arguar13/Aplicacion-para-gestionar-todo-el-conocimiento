import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:sinapsis/core/domain/entities/chat_source.dart';
import 'package:sinapsis/features/ai_organize/domain/services/map_note_intro.dart';
import 'package:sinapsis/features/ai_organize/domain/services/space_chooser.dart';
import 'package:sinapsis/features/ai_organize/domain/services/topic_parent_chooser.dart';
import 'package:sinapsis/features/ai_organize/domain/services/vocabulary_budget.dart';
import 'package:sinapsis/features/chat/data/services/gemma_chat_session.dart';
import 'package:sinapsis/features/chat/data/services/gemma_engine.dart';
import 'package:sinapsis/features/chat/data/services/gemma_reply.dart';
import 'package:sinapsis/features/chat/domain/entities/language_model_performance.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_gate.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_meter.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcard_draft_parser.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcard_generator.dart';
import 'package:sinapsis/features/flashcards/domain/services/quiz_question_generator.dart';
import 'package:sinapsis/features/graph/domain/services/relation_suggestion_parser.dart';
import 'package:sinapsis/features/graph/domain/services/relation_suggestion_service.dart';
import 'package:sinapsis/features/library/domain/services/summarization_service.dart';
import 'package:sinapsis/features/notebooks/domain/services/notebook_candidates.dart';
import 'package:sinapsis/features/notebooks/domain/services/notebook_suggestions.dart';
import 'package:sinapsis/features/notes/domain/services/derived_claim_anchor.dart';
import 'package:sinapsis/features/notes/domain/services/derived_note_generator.dart';
import 'package:sinapsis/features/notes/domain/services/derived_note_parts.dart';
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

/// Mismo criterio que `_spaceChoiceSystemInstruction` (F30, «Crear con IA»):
/// elegir en una lista numerada, en una sola línea de formato exacto, sin
/// inventar nada. Para el cuaderno que pidió la persona, no para clasificar.
const _notebookPicksSystemInstruction =
    'Respondé siempre en español. Tu única tarea es decidir cuáles '
    'elementos de una lista numerada sirven para un cuaderno sobre el tema '
    'que pide la persona, basándote ÚNICAMENTE en sus títulos y fragmentos. '
    'Un elemento sirve si trata del tema o de una parte de él, aunque no lo '
    'nombre igual. Respondé UNA sola línea con este formato exacto, sin '
    'Markdown:\nVAN: <números de los que sirven, separados por comas>\nSi '
    'ninguno sirve, respondé exactamente: VAN: ninguno. No respondas nada '
    'más.';

/// El nombre de un cuaderno sugerido (F30): uno por tema de una lista
/// numerada, en una línea de formato exacto cada uno, y sin inventar nada que
/// no esté en lo que se le da.
const _notebookNamesSystemInstruction =
    'Respondé siempre en español. Tu única tarea es proponer, para cada tema '
    'de una lista numerada, un nombre corto para un cuaderno que reúna sus '
    'elementos (hasta seis palabras) y, solo si aporta algo, una línea de '
    'hasta quince palabras que diga qué reúne, basándote ÚNICAMENTE en el '
    'nombre del tema y en los títulos de ejemplo: nunca agregues datos que no '
    'estén ahí. Respondé UNA línea por tema con este formato exacto, sin '
    'Markdown:\nCUADERNO: <número> | <nombre> | <descripción>\nSi la '
    'descripción no aporta, dejala vacía. No respondas nada más.';

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

/// Cuánto puede escribir el modelo, como mucho, en cada uso (F30): un tope de
/// tokens por respuesta (`maxOutputTokens`).
///
/// Sin tope, el modelo escribe hasta que decide terminar —o hasta llenar la
/// ventana—, y un modelo chico a veces no decide: repite, se va por las
/// ramas. Cada token cuesta lo mismo de escribir, así que el tope es la
/// espera más larga posible. Va por uso: una charla necesita párrafos; elegir
/// un tema, una línea.
///
/// Una respuesta del chat: unas 350 palabras, de sobra para «breve y
/// directa», y deja lugar en la ventana de 2048 para la instrucción, lo
/// conversado y el contexto de la bóveda.
const kChatReplyTokens = 512;

/// Un resumen: dos o tres párrafos cortos.
const kSummaryReplyTokens = 512;

/// Las líneas `PROPIEDAD:` de un elemento: unas pocas.
const kPropertiesReplyTokens = 192;

/// Una sola línea de elección —`TEMA:` o `PADRE:`—, con margen.
const kChoiceReplyTokens = 48;

/// La introducción de una nota mapa: dos o tres oraciones.
const kMapIntroReplyTokens = 192;

/// Una línea `VAN:` con los números de una tanda (`kNotebookJudgeBatch`).
const kNotebookPicksReplyTokens = 64;

/// Una línea `CUADERNO:` por cada uno de [count] temas: un nombre y una línea
/// de descripción, unos 48 tokens, y un margen.
int notebookNamesReplyTokens(int count) => (count * 48 + 32).clamp(96, 384);

/// Una guía de estudio, preguntas, un esquema o una cronología: lo más largo
/// que se le pide, con la frase de origen de cada afirmación.
const kDerivedNoteReplyTokens = 768;

/// Lo que se deja libre en la ventana, además de lo contado, para las marcas
/// de turno que el formato del modelo agrega alrededor de cada mensaje.
const kPromptMarginTokens = 32;

/// [count] tarjetas o preguntas, con su respuesta y la frase de la que sale
/// cada una: unos 96 tokens cada una, y un margen.
int draftsReplyTokens(int count) => (count * 96 + 32).clamp(192, 1024);

/// Una línea `SUGERENCIA:` por cada uno de [candidates] candidatos, como
/// mucho.
int relationsReplyTokens(int candidates) =>
    (candidates * 40 + 32).clamp(96, 768);

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
        QuizQuestionGenerator,
        NotebookCandidateJudge,
        NotebookNamer {
  /// Cada uso pasa por [gate] (F27): esta instancia es la de la persona —el
  /// chat, resumir, las tarjetas y el quiz a mano— y [background], la de la
  /// cola de la IA.
  ///
  /// [engine] es el modelo cargado, compartido con [background]; [meter],
  /// dónde queda lo que tardó cada respuesta (F30).
  ///
  /// [countTokens] cuenta con el tokenizador del modelo lo que ocupa un texto
  /// en la ventana de una charla.
  GemmaChatModel({
    required LanguageModelGate gate,
    required GemmaEngine engine,
    required LanguageModelMeter meter,
    GemmaTokenCounter countTokens = countGemmaTokens,
  }) : this._(gate, engine, meter, countTokens, inBackground: false);

  GemmaChatModel._(
    this._gate,
    this._engine,
    this._meter,
    this._countTokens, {
    required bool inBackground,
  }) : _inBackground = inBackground;

  final GemmaTokenCounter _countTokens;

  final LanguageModelGate _gate;

  /// El modelo cargado, compartido con [background]: son los mismos pesos.
  final GemmaEngine _engine;

  final LanguageModelMeter _meter;

  final bool _inBackground;

  /// El mismo modelo ya cargado, pero con el turno de la cola de la IA (F27):
  /// espera a que la persona no lo esté usando y le cede el paso. Es lo que
  /// reciben los pasos de la IA que organiza sola; nunca la interfaz.
  late final GemmaChatModel background = _inBackground
      ? this
      : GemmaChatModel._(
          _gate,
          _engine,
          _meter,
          _countTokens,
          inBackground: true,
        );

  /// Corre [work] con el modelo cargado, en el turno que le toca a esta
  /// instancia. Todo método que abre una sesión pasa por acá: dos sesiones a
  /// la vez se pisan la única que tiene `flutter_gemma` (ver
  /// `LanguageModelGate`).
  ///
  /// En la cola de la IA, si la persona pide el modelo a mitad, el trabajo
  /// se corta ([_preempt]) y se repite entero cuando ella lo suelte (F30):
  /// cada [work] abre su propia sesión y lee su respuesta de cero, así que
  /// repetirlo no deja nada a medias.
  Future<T> _withTurn<T>(Future<T> Function(InferenceModel model) work) async {
    if (!_inBackground) {
      return _gate.runForUser(() async => work(await _engine.model()));
    }
    while (true) {
      try {
        return await _gate.runInBackground(() async {
          _preempted = false;
          return work(await _engine.model());
        }, onPreempt: _preempt);
      } on _PreemptedByUser {
        // La persona pidió el modelo: se vuelve a pedir el turno, que espera
        // a que termine.
      }
    }
  }

  /// Si la persona pidió el modelo mientras la cola lo usaba.
  var _preempted = false;

  /// La sesión que está escribiendo ahora, para cortarla.
  InferenceChat? _generating;

  /// Corta lo que la cola esté escribiendo: `stopGeneration` lo termina en el
  /// acto, y [_generate] lo descarta.
  void _preempt() {
    _preempted = true;
    unawaited(_generating?.stopGeneration());
  }

  /// La respuesta entera de [chat]. En la cola, si la persona pidió el
  /// modelo antes o durante, no la da: corta el trabajo para repetirlo.
  Future<String> _generate(InferenceChat chat) async {
    if (_preempted) throw const _PreemptedByUser();
    _generating = chat;
    try {
      final text = await collectReply(chat, meter: _meter);
      if (_preempted) throw const _PreemptedByUser();
      return text;
    } finally {
      _generating = null;
    }
  }

  @override
  Future<String> answer({
    required String question,
    required List<ChatSource> sources,
  }) {
    return _withTurn((model) async {
      final chat = await model.createChat(
        systemInstruction: _systemInstruction,
        maxOutputTokens: kChatReplyTokens,
      );

      try {
        await chat.addQueryChunk(
          Message.text(
            text: _buildVaultPrompt(question, sources),
            isUser: true,
          ),
        );
        return await _generate(chat);
      } finally {
        await chat.close();
      }
    });
  }

  @override
  Future<void> warmUp() async {
    if (_engine.isLoaded) return;
    await _gate.runForUser(_engine.model, preempt: false);
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
  ///
  /// La sesión lleva su propia cuenta de la ventana (F30, ver
  /// `GemmaChatSession`): por eso `tokenBuffer: 0`, que apaga el recorte de
  /// `flutter_gemma` —cuenta solo lo que escribe el modelo y, al pasarse,
  /// junta todo lo conversado en un solo mensaje—.
  Future<GemmaChatSession> _openConversation(String systemInstruction) async {
    final session = GemmaChatSession(
      _gate,
      () async => (await _engine.model()).createChat(
        systemInstruction: systemInstruction,
        maxOutputTokens: kChatReplyTokens,
        tokenBuffer: 0,
      ),
      reply: (chat) =>
          measuredReply(chat, meter: _meter, kind: LanguageModelReplyKind.chat),
      clean: cleanReply,
      instruction: systemInstruction,
      window: _engine.contextTokens,
      replyTokens: kChatReplyTokens,
      prepareImages: () => _engine.model(vision: true),
      loadCount: () => _engine.loadCount,
      countTokens: _countTokens,
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
        maxOutputTokens: draftsReplyTokens(count),
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
        final text = await _generate(chat);

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
        maxOutputTokens: draftsReplyTokens(count),
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
        final text = await _generate(chat);

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
        maxOutputTokens: kSummaryReplyTokens,
      );

      try {
        await chat.addQueryChunk(Message.text(text: content, isUser: true));
        return await _generate(chat);
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
        maxOutputTokens: relationsReplyTokens(candidates.length),
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
        final text = await _generate(chat);

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
        maxOutputTokens: kPropertiesReplyTokens,
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
        final text = await _generate(chat);

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
        maxOutputTokens: kChoiceReplyTokens,
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
        final text = await _generate(chat);
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
        maxOutputTokens: kChoiceReplyTokens,
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
        final text = await _generate(chat);
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
        maxOutputTokens: kMapIntroReplyTokens,
      );

      try {
        await chat.addQueryChunk(
          Message.text(
            text: buildMapIntroPrompt(topic: topic, entries: entries),
            isUser: true,
          ),
        );
        return await _generate(chat);
      } finally {
        await chat.close();
      }
    });
  }

  /// Cuáles de [candidates] van en un cuaderno sobre [topic] (F30, «Crear con
  /// IA»): lo pide la persona, así que va con su turno.
  @override
  Future<Set<int>?> judgeNotebookCandidates({
    required String topic,
    required List<({String title, String excerpt})> candidates,
  }) {
    if (candidates.isEmpty) return Future.value(const <int>{});

    return _withTurn((model) async {
      final chat = await model.createChat(
        systemInstruction: _notebookPicksSystemInstruction,
        maxOutputTokens: kNotebookPicksReplyTokens,
      );

      try {
        await chat.addQueryChunk(
          Message.text(
            text: buildNotebookPicksPrompt(topic, candidates),
            isUser: true,
          ),
        );
        final text = await _generate(chat);
        return parseNotebookPicks(text, count: candidates.length);
      } finally {
        await chat.close();
      }
    });
  }

  /// Un nombre —y, si aporta, una línea— para cada cuaderno sugerido (F30):
  /// lo pide la persona al abrir los sugeridos, así que va con su turno.
  @override
  Future<Map<int, NotebookNaming>> nameNotebooks(
    List<NotebookNamingInput> inputs,
  ) {
    if (inputs.isEmpty) return Future.value(const {});

    return _withTurn((model) async {
      final chat = await model.createChat(
        systemInstruction: _notebookNamesSystemInstruction,
        maxOutputTokens: notebookNamesReplyTokens(inputs.length),
      );

      try {
        await chat.addQueryChunk(
          Message.text(text: buildNotebookNamesPrompt(inputs), isUser: true),
        );
        final text = await _generate(chat);
        return parseNotebookNames(text, count: inputs.length);
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
      final instruction = _derivedSystemInstructionFor(type);
      final chat = await model.createChat(
        systemInstruction: instruction,
        maxOutputTokens: kDerivedNoteReplyTokens,
      );

      try {
        // Nunca más de lo que entra (F30): con el tokenizador del modelo, lo
        // que queda de la ventana después de la instrucción y la respuesta
        // más larga. Quien llama ya reparte en partes que suelen entrar;
        // esto lo garantiza aunque el texto cuente más tokens de lo común.
        final fitted = await fitSourcesToWindow(
          sources,
          roomTokens:
              _engine.contextTokens -
              kDerivedNoteReplyTokens -
              await _countTokens(chat, instruction) -
              kPromptMarginTokens,
          countTokens: (text) => _countTokens(chat, text),
          build: _buildDerivedPrompt,
        );
        if (fitted.isEmpty) {
          return DerivedNoteDraft(type: type, sections: const []);
        }

        await chat.addQueryChunk(
          Message.text(text: _buildDerivedPrompt(fitted), isUser: true),
        );
        final text = await _generate(chat);

        final raw = parseDerivedNoteResponse(text);
        final sections = anchorDerivedClaims(raw, fitted);
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
  ChatReplyStream send(String message, {List<Uint8List> images = const []}) =>
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
  ChatReplyStream send({
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

/// El pedido de «Crear con IA» (F30): el tema, de hasta 200 caracteres, y la
/// lista numerada con el título y el fragmento de cada uno, ya cortos
/// (`kNotebookExcerptChars`): una tanda entra holgada en la ventana.
String buildNotebookPicksPrompt(
  String topic,
  List<({String title, String excerpt})> candidates,
) {
  final shortTopic = topic.trim().length <= 200
      ? topic.trim()
      : topic.trim().substring(0, 200);
  final list = [
    for (final (i, c) in candidates.indexed)
      [
        '${i + 1}. ${_short(c.title, 120)}',
        _short(c.excerpt, kNotebookExcerptChars),
      ].join('\n'),
  ].join('\n\n');
  return 'Tema del cuaderno: $shortTopic\n\nElementos:\n$list';
}

/// El pedido de nombres de cuadernos sugeridos (F30): cada tema, con cuántos
/// elementos tiene y algunos títulos de ejemplo, cortos.
String buildNotebookNamesPrompt(List<NotebookNamingInput> inputs) {
  final list = [
    for (final (i, input) in inputs.indexed)
      [
        '${i + 1}. ${_short(input.topic, 80)} (${input.itemCount} elementos)',
        if (input.titles.isNotEmpty)
          'Ejemplos: ${input.titles.map((t) => _short(t, 80)).join('; ')}',
      ].join('\n'),
  ].join('\n\n');
  return 'Temas:\n$list';
}

String _short(String text, int max) {
  final trimmed = text.trim();
  return trimmed.length <= max ? trimmed : '${trimmed.substring(0, max)}…';
}

/// La persona pidió el modelo mientras la cola de la IA lo usaba: el trabajo
/// se cortó y se repite (ver `GemmaChatModel._withTurn`).
class _PreemptedByUser implements Exception {
  const _PreemptedByUser();
}
