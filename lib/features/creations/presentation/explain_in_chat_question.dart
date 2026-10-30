/// La pregunta de «Explicar» (F43, M15, decisión L): lo que se le pregunta
/// al chat sobre una pregunta del cuestionario o una tarjeta, ya escrito en el
/// idioma de la app y con todo su contexto. Es una función pura: la arma
/// [explainInChatQuestion] con lo que sabe [ExplainSubject], y la prueban sin
/// dibujar nada.
library;

import 'package:flutter/foundation.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo más largo que viaja del pasaje de la fuente: alcanza para ubicar la
/// pregunta, y no le llena la ventana al modelo con medio capítulo.
const kExplainPassageChars = 600;

/// Una opción de lo que se explica: su texto, si es la correcta y si se la
/// eligió.
@immutable
class ExplainOption {
  const ExplainOption({
    required this.text,
    this.correct = false,
    this.chosen = false,
  });

  final String text;
  final bool correct;
  final bool chosen;

  @override
  bool operator ==(Object other) =>
      other is ExplainOption &&
      other.text == text &&
      other.correct == correct &&
      other.chosen == chosen;

  @override
  int get hashCode => Object.hash(text, correct, chosen);
}

/// Lo que se le explica al chat: una pregunta del cuestionario o una
/// tarjeta, con lo que se sabe de ella.
///
/// Mientras no se respondió ([answered] falso), la respuesta y cuál es la
/// correcta pueden venir —quien arma esto no tiene por qué separarlas—, pero
/// [explainInChatQuestion] no las usa: antes de responder se explica la
/// pregunta sin decir cuál es.
@immutable
class ExplainSubject {
  const ExplainSubject({
    required this.question,
    this.options = const [],
    this.answer,
    this.typed,
    this.typedCorrect,
    this.answered = false,
    this.sourceTitle,
    this.passage,
  });

  /// La pregunta, o el frente de la tarjeta.
  final String question;

  /// Las opciones, en el orden en que se ven (A, B, C…); vacía si no tiene.
  final List<ExplainOption> options;

  /// La respuesta: el dorso de la tarjeta, lo que falta en una de completar,
  /// la esperada en una breve.
  final String? answer;

  /// Lo que se escribió, si se contestó escribiendo.
  final String? typed;

  /// Si lo escrito estaba bien; `null` si no se sabe (un «casi», o la
  /// respuesta breve que nadie calificó).
  final bool? typedCorrect;

  /// Si ya se respondió (o se dio vuelta la tarjeta).
  final bool answered;

  /// El título del documento del que sale, si se sabe.
  final String? sourceTitle;

  /// El pasaje del documento del que sale, si se sabe.
  final String? passage;

  /// La misma, con su fuente.
  ExplainSubject withSource({String? title, String? passage}) => ExplainSubject(
    question: question,
    options: options,
    answer: answer,
    typed: typed,
    typedCorrect: typedCorrect,
    answered: answered,
    sourceTitle: title ?? sourceTitle,
    passage: passage ?? this.passage,
  );

  @override
  bool operator ==(Object other) =>
      other is ExplainSubject &&
      other.question == question &&
      listEquals(other.options, options) &&
      other.answer == answer &&
      other.typed == typed &&
      other.typedCorrect == typedCorrect &&
      other.answered == answered &&
      other.sourceTitle == sourceTitle &&
      other.passage == passage;

  @override
  int get hashCode => Object.hash(
    question,
    Object.hashAll(options),
    answer,
    typed,
    typedCorrect,
    answered,
    sourceTitle,
    passage,
  );
}

/// La pregunta para el chat sobre [subject], en el idioma de [l10n]:
///
/// - **antes de responder**, que explique la pregunta **sin decir cuál es la
///   correcta**: van la pregunta y las opciones, nunca la respuesta;
/// - **después**, por qué la correcta es esa y —si se eligió otra— por qué la
///   elegida no: van las opciones, la correcta, la elegida o lo escrito, y la
///   respuesta;
/// - una **tarjeta** dada vuelta pide la explicación de su respuesta.
///
/// Debajo, la fuente: el título del documento y el pasaje, si se saben. Así
/// la búsqueda en la bóveda va a ellos.
String explainInChatQuestion(AppLocalizations l10n, ExplainSubject subject) {
  final options = subject.options;
  final answered = subject.answered;
  final answer = _clean(subject.answer);
  final typed = _clean(subject.typed);
  String quote(String text) => l10n.f43S19Quote(text);
  String option(int i) => quote('${_letter(i)}. ${_clean(options[i].text)}');
  String list(List<String> items) => items.length == 1
      ? items.single
      : l10n.f43S19ListPair(
          items.sublist(0, items.length - 1).join(', '),
          items.last,
        );

  final String ask;
  if (!answered) {
    ask = l10n.f43S19AskBefore;
  } else if (options.isNotEmpty) {
    final correct = [
      for (final (i, o) in options.indexed)
        if (o.correct) option(i),
    ];
    final chosen = [
      for (final (i, o) in options.indexed)
        if (o.chosen) option(i),
    ];
    final right =
        chosen.isNotEmpty && options.every((o) => o.correct == o.chosen);
    if (correct.isEmpty) {
      // Una pregunta sin correcta marcada (un dato roto): se pide la
      // explicación sin afirmar nada.
      ask = l10n.f43S19AskCard;
    } else if (chosen.isEmpty) {
      ask = l10n.f43S19AskChoiceShown(list(correct));
    } else if (right) {
      ask = l10n.f43S19AskChoiceRight(list(chosen));
    } else {
      ask = l10n.f43S19AskChoiceWrong(list(chosen), list(correct));
    }
  } else if (typed.isNotEmpty) {
    ask = switch (subject.typedCorrect) {
      true => l10n.f43S19AskTypedRight(quote(typed)),
      false => l10n.f43S19AskTypedWrong(quote(typed)),
      null => l10n.f43S19AskTyped(quote(typed)),
    };
  } else {
    ask = l10n.f43S19AskCard;
  }

  final title = _clean(subject.sourceTitle);
  final passage = _clean(subject.passage);
  return [
    ask,
    '',
    l10n.f43S19LineQuestion(_clean(subject.question)),
    if (options.isNotEmpty) ...[
      l10n.f43S19LineOptions,
      for (var i = 0; i < options.length; i++)
        '${_letter(i)}. ${_clean(options[i].text)}',
    ],
    // La respuesta solo después: antes, ni el dorso ni lo esperado.
    if (answered && answer.isNotEmpty) l10n.f43S19LineAnswer(answer),
    if (title.isNotEmpty || passage.isNotEmpty) '',
    if (title.isNotEmpty) l10n.f43S19LineSource(title),
    if (passage.isNotEmpty) l10n.f43S19LinePassage(quote(passage)),
  ].join('\n');
}

/// El pasaje de [text] entre [start] y [end] —las posiciones de la tarjeta en
/// su fuente—, en una sola línea y con [kExplainPassageChars] como mucho.
/// Vacío si el tramo no cae en el texto (el texto se rehízo después).
String explainPassage(String text, int start, int end) {
  if (start < 0 || end <= start || start >= text.length) return '';
  final piece = _clean(text.substring(start, end.clamp(start, text.length)));
  if (piece.length <= kExplainPassageChars) return piece;
  final cut = piece.substring(0, kExplainPassageChars);
  // Se corta en la última palabra entera, si hay una cerca.
  final space = cut.lastIndexOf(' ');
  final kept = space > kExplainPassageChars * 0.8
      ? cut.substring(0, space)
      : cut;
  return '${kept.trimRight()}…';
}

/// La letra de la opción [index]: A, B, C…
String _letter(int index) => String.fromCharCode(65 + index);

/// [text] sin espacios de más ni saltos de línea: cada dato, en su renglón.
String _clean(String? text) =>
    (text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
