import 'package:meta/meta.dart';

/// Cuántas sugerencias se muestran como mucho en el chat vacío (F42): tres o
/// cuatro, como en las apps de referencia; más ya es una lista que leer.
const kMaxChatSuggestions = 4;

/// Una sugerencia tocable del chat vacío (F42), armada con lo del dueño: lo
/// último que guardó y ya se procesó, el tema con más cosas, el cuaderno
/// elegido.
///
/// Las que son una pregunta entera se mandan al tocarlas ([sendsAtOnce]);
/// las que necesitan que la persona la termine —«¿Qué dice «X» sobre…?»—
/// solo llenan el campo y dejan el cursor al final. Cómo se dice cada una es
/// cosa de la pantalla, en el idioma de la app.
@immutable
sealed class ChatSuggestion {
  const ChatSuggestion();

  /// Si tocarla la manda; si no, la escribe en el campo para completarla.
  bool get sendsAtOnce;
}

/// «Resumime «[title]»»: lo último que se guardó.
final class SummarizeItemSuggestion extends ChatSuggestion {
  const SummarizeItemSuggestion(this.title);

  final String title;

  @override
  bool get sendsAtOnce => true;

  @override
  bool operator ==(Object other) =>
      other is SummarizeItemSuggestion && other.title == title;

  @override
  int get hashCode => Object.hash(SummarizeItemSuggestion, title);
}

/// «Preguntame sobre «[title]»»: estudiar algo guardado, charlando.
final class QuizMeSuggestion extends ChatSuggestion {
  const QuizMeSuggestion(this.title);

  final String title;

  @override
  bool get sendsAtOnce => true;

  @override
  bool operator ==(Object other) =>
      other is QuizMeSuggestion && other.title == title;

  @override
  int get hashCode => Object.hash(QuizMeSuggestion, title);
}

/// «¿Qué dice «[title]» sobre…?»: la persona dice sobre qué.
final class AskItemSuggestion extends ChatSuggestion {
  const AskItemSuggestion(this.title);

  final String title;

  @override
  bool get sendsAtOnce => false;

  @override
  bool operator ==(Object other) =>
      other is AskItemSuggestion && other.title == title;

  @override
  int get hashCode => Object.hash(AskItemSuggestion, title);
}

/// «¿Qué tengo guardado sobre [topic]?»: el tema con más elementos.
final class ExploreTopicSuggestion extends ChatSuggestion {
  const ExploreTopicSuggestion(this.topic);

  final String topic;

  @override
  bool get sendsAtOnce => true;

  @override
  bool operator ==(Object other) =>
      other is ExploreTopicSuggestion && other.topic == topic;

  @override
  int get hashCode => Object.hash(ExploreTopicSuggestion, topic);
}

/// «¿Qué ideas se repiten en «[notebook]»?»: con la pregunta acotada a un
/// cuaderno, en vez del tema.
final class NotebookThemesSuggestion extends ChatSuggestion {
  const NotebookThemesSuggestion(this.notebook);

  final String notebook;

  @override
  bool get sendsAtOnce => true;

  @override
  bool operator ==(Object other) =>
      other is NotebookThemesSuggestion && other.notebook == notebook;

  @override
  int get hashCode => Object.hash(NotebookThemesSuggestion, notebook);
}

/// Un comienzo para la conversación libre, que no busca en la bóveda: no hay
/// nada de lo guardado que proponer, solo cómo empezar.
enum FreeChatStarter { explain, brainstorm, draft }

/// Una sugerencia de la conversación libre: se termina en el campo.
final class FreeStarterSuggestion extends ChatSuggestion {
  const FreeStarterSuggestion(this.starter);

  final FreeChatStarter starter;

  @override
  bool get sendsAtOnce => false;

  @override
  bool operator ==(Object other) =>
      other is FreeStarterSuggestion && other.starter == starter;

  @override
  int get hashCode => Object.hash(FreeStarterSuggestion, starter);
}

/// Las sugerencias del chat con la bóveda, de lo más concreto a lo más
/// amplio, hasta [kMaxChatSuggestions]:
///
/// 1. resumir lo último guardado ([recentTitles] primero, lo más nuevo);
/// 2. que pregunte sobre el anterior —o sobre el mismo, si hay uno solo—;
/// 3. qué dice el tercero sobre algo, para completar;
/// 4. qué ideas se repiten en el cuaderno elegido ([notebookName]) o, en
///    toda la bóveda, qué hay guardado del tema con más cosas ([topTopic]).
///
/// Los títulos vacíos o repetidos no cuentan. Sin nada guardado ni tema, no
/// hay sugerencias: la pantalla lo dice.
List<ChatSuggestion> vaultChatSuggestions({
  required List<String> recentTitles,
  String? topTopic,
  String? notebookName,
}) {
  final titles = <String>[];
  for (final raw in recentTitles) {
    final title = raw.trim();
    if (title.isNotEmpty && !titles.contains(title)) titles.add(title);
  }
  final topic = topTopic?.trim();
  final notebook = notebookName?.trim();
  return [
    if (titles.isNotEmpty) SummarizeItemSuggestion(titles.first),
    if (titles.isNotEmpty) QuizMeSuggestion(titles[titles.length > 1 ? 1 : 0]),
    if (titles.length > 2) AskItemSuggestion(titles[2]),
    if (notebook != null && notebook.isNotEmpty)
      NotebookThemesSuggestion(notebook)
    else if (topic != null && topic.isNotEmpty)
      ExploreTopicSuggestion(topic),
  ].take(kMaxChatSuggestions).toList();
}

/// Las sugerencias de la conversación libre: tres comienzos.
const freeChatSuggestions = [
  FreeStarterSuggestion(FreeChatStarter.explain),
  FreeStarterSuggestion(FreeChatStarter.brainstorm),
  FreeStarterSuggestion(FreeChatStarter.draft),
];
