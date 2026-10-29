import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/services/ai_rejection_fingerprint.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/creations/flashcards/domain/flashcard_deck.dart'
    show studyImageFailureNamed;
import 'package:sinapsis/features/creations/flashcards/domain/study_item_json.dart';
import 'package:sinapsis/features/creations/flashcards/domain/study_items.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';

/// Los cuatro tipos de pregunta del cuestionario (F43, paso 8), con el valor
/// que guarda la hoja de personalizar (`CreationOptionValues`).
enum QuizQuestionType {
  /// Una sola opción correcta, entre cuatro.
  single(CreationOptionValues.single),

  /// Todas las que correspondan: una o más correctas.
  multiple(CreationOptionValues.multiple),

  /// Completar el espacio: se escribe lo que falta.
  fillBlank(CreationOptionValues.fillBlank),

  /// Una respuesta breve, escrita.
  shortAnswer(CreationOptionValues.shortAnswer);

  const QuizQuestionType(this.storageKey);

  final String storageKey;

  bool get hasOptions => this == single || this == multiple;

  bool get isTyped => !hasOptions;

  static QuizQuestionType? fromStorageKey(String? key) {
    for (final type in values) {
      if (type.storageKey == key) return type;
    }
    return null;
  }
}

/// Los topes de cada campo de una pregunta.
abstract final class QuizLimits {
  static const int questions = 40;
  static const int options = 6;
  static const int title = 120;
  static const int question = 600;
  static const int option = 300;
  static const int explanation = 700;
  static const int answer = 400;
  static const int hint = 200;
  static const int prompt = 500;
}

/// Lo que va en el espacio de una pregunta de completar.
const kQuizBlank = '_____';

/// Una opción de una pregunta, con la explicación de por qué es o no es
/// correcta: lo que se muestra debajo de cada una al responder.
@immutable
class QuizOption {
  const QuizOption({
    required this.text,
    required this.correct,
    this.explanation = '',
  });

  final String text;
  final bool correct;
  final String explanation;

  @override
  bool operator ==(Object other) =>
      other is QuizOption &&
      other.text == text &&
      other.correct == correct &&
      other.explanation == explanation;

  @override
  int get hashCode => Object.hash(text, correct, explanation);
}

/// Una pregunta del cuestionario.
@immutable
class QuizQuestion implements StudyItem<QuizQuestion> {
  const QuizQuestion({
    required this.id,
    required this.type,
    required this.prompt,
    this.options = const [],
    this.answer = '',
    this.alternatives = const [],
    this.explanation = '',
    this.hint = '',
    this.sourceHint = '',
    this.documentId,
    this.icon,
    this.illustrationPrompt = '',
    this.illustrationRef,
  });

  /// Estable dentro del cuestionario (`q1`, `q2`…): une la pregunta con su
  /// ilustración y con lo que se respondió.
  final String id;
  final QuizQuestionType type;

  /// La pregunta; en una de completar, con [kQuizBlank] donde va lo que falta.
  final String prompt;

  /// Las opciones, en el orden en que se muestran (A, B, C, D): ya
  /// mezcladas al generarse —la IA tiende a poner la correcta primero—.
  final List<QuizOption> options;

  /// Lo que falta (completar) o la respuesta esperada (respuesta breve).
  final String answer;

  /// Otras formas que también valen, en una de completar.
  final List<String> alternatives;

  /// Por qué la respuesta es esa.
  final String explanation;
  final String hint;

  @override
  final String sourceHint;

  @override
  final String? documentId;

  final String? icon;
  final String illustrationPrompt;

  /// Dónde está guardada su ilustración con IA (`CreationIllustrationStore`),
  /// si se pidió y salió.
  final String? illustrationRef;

  /// Cuáles son las correctas, por su lugar.
  Set<int> get correctIndexes => {
    for (final (i, option) in options.indexed)
      if (option.correct) i,
  };

  @override
  String get fingerprint => flashcardRejectionFingerprint(prompt);

  @override
  QuizQuestion withDocument(String documentId) =>
      copyWith(documentId: documentId);

  QuizQuestion copyWith({
    String? id,
    String? documentId,
    List<QuizOption>? options,
    String? illustrationRef,
  }) => QuizQuestion(
    id: id ?? this.id,
    type: type,
    prompt: prompt,
    options: options ?? this.options,
    answer: answer,
    alternatives: alternatives,
    explanation: explanation,
    hint: hint,
    sourceHint: sourceHint,
    documentId: documentId ?? this.documentId,
    icon: icon,
    illustrationPrompt: illustrationPrompt,
    illustrationRef: illustrationRef ?? this.illustrationRef,
  );

  @override
  bool operator ==(Object other) =>
      other is QuizQuestion &&
      other.id == id &&
      other.type == type &&
      other.prompt == prompt &&
      listEquals(other.options, options) &&
      other.answer == answer &&
      listEquals(other.alternatives, alternatives) &&
      other.explanation == explanation &&
      other.hint == hint &&
      other.documentId == documentId &&
      other.icon == icon &&
      other.illustrationPrompt == illustrationPrompt &&
      other.illustrationRef == illustrationRef;

  @override
  int get hashCode => Object.hash(
    id,
    type,
    prompt,
    Object.hashAll(options),
    answer,
    Object.hashAll(alternatives),
    explanation,
    hint,
    documentId,
    icon,
    illustrationPrompt,
    illustrationRef,
  );

  @override
  String toString() => 'QuizQuestion($id, ${type.storageKey}, $prompt)';
}

/// Un cuestionario (F43, paso 8): lo que se guarda en el contenido de la
/// creación.
@immutable
class Quiz {
  const Quiz({
    required this.title,
    required this.questions,
    this.illustrationFailure,
    this.illustrationAccount,
  });

  final String title;
  final List<QuizQuestion> questions;
  final ImageFailure? illustrationFailure;
  final String? illustrationAccount;

  bool get isEmpty => questions.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is Quiz &&
      other.title == title &&
      listEquals(other.questions, questions) &&
      other.illustrationFailure == illustrationFailure &&
      other.illustrationAccount == illustrationAccount;

  @override
  int get hashCode => Object.hash(
    title,
    Object.hashAll(questions),
    illustrationFailure,
    illustrationAccount,
  );
}

/// El JSON de un cuestionario, en los dos sentidos (F43, decisión G).
///
/// [tryDecode] lee con tolerancia: claves en castellano o en inglés, el tipo
/// escrito de muchas maneras (`opcion_unica`, `single_choice`, `cloze`,
/// `abierta`…) o deducido de lo que trae, las opciones como objetos o como
/// textos con la correcta aparte (`"correcta": "B"` o `"answer": 2`). Una
/// pregunta que no se puede contestar —sin opción correcta, de completar sin
/// lo que falta— no cuenta; una de opción única con dos correctas pasa a ser
/// de selección múltiple. Devuelve `null` solo si no queda ninguna.
abstract final class QuizJson {
  static const _titleKeys = ['title', 'titulo', 'name', 'nombre'];
  static const _questionsKeys = ['questions', 'preguntas', 'items', 'quiz'];
  static const _promptKeys = ['question', 'pregunta', 'prompt', 'enunciado'];
  static const _optionsKeys = ['options', 'opciones', 'choices', 'answers'];
  static const _optionTextKeys = ['text', 'texto', 'option', 'opcion'];
  static const _correctKeys = ['correct', 'correcta', 'correcto', 'is_correct'];
  static const _explanationKeys = [
    'explanation',
    'explicacion',
    'rationale',
    'why',
    'porque',
  ];
  static const _answerKeys = [
    'answer',
    'respuesta',
    'expected_answer',
    'respuesta_esperada',
    'blank',
    'correct_answer',
    'respuesta_correcta',
  ];
  static const _alternativesKeys = [
    'alternatives',
    'alternativas',
    'accepted',
    'aceptadas',
  ];

  static Quiz? tryDecode(Object? source) {
    final json = source is String ? _decodeText(source) : source;
    final Map<String, Object?> quiz;
    if (json is List) {
      quiz = {'questions': json};
    } else if (studyJsonObject(json) case final map?) {
      quiz = map;
    } else {
      return null;
    }
    final questions = <QuizQuestion>[];
    final seen = <String>{};
    final ids = <String>{};
    for (final raw in studyJsonList(quiz, _questionsKeys)) {
      var question = _question(raw, questions.length);
      if (question == null || !seen.add(question.fingerprint)) continue;
      if (!ids.add(question.id)) {
        var n = ids.length + 1;
        while (!ids.add('q$n')) {
          n++;
        }
        question = question.copyWith(id: 'q$n');
      }
      questions.add(question);
      if (questions.length == QuizLimits.questions) break;
    }
    if (questions.isEmpty) return null;
    final account = studyJsonText(quiz, const [
      'illustration_account',
    ], max: 80);
    return Quiz(
      title: studyJsonText(quiz, _titleKeys, max: QuizLimits.title),
      questions: questions,
      illustrationFailure: studyImageFailureNamed(
        studyJsonText(quiz, const ['illustration_failure']),
      ),
      illustrationAccount: account.isEmpty ? null : account,
    );
  }

  static Quiz decode(Object? source) =>
      tryDecode(source) ?? const Quiz(title: '', questions: []);

  static Quiz parse(Object? json) =>
      tryDecode(json) ??
      (throw const FormatException(
        'No trae ninguna pregunta que se pueda contestar: cada una necesita '
        '"pregunta" y, según su tipo, "opciones" con una "correcta" o la '
        '"respuesta".',
      ));

  static Map<String, Object?> encode(Quiz quiz) => {
    'title': quiz.title,
    if (quiz.illustrationFailure case final failure?)
      'illustration_failure': failure.name,
    if (quiz.illustrationAccount case final account?)
      'illustration_account': account,
    'questions': [
      for (final q in quiz.questions)
        {
          'id': q.id,
          'type': q.type.storageKey,
          'question': q.prompt,
          if (q.options.isNotEmpty)
            'options': [
              for (final option in q.options)
                {
                  'text': option.text,
                  'correct': option.correct,
                  if (option.explanation.isNotEmpty)
                    'explanation': option.explanation,
                },
            ],
          if (q.answer.isNotEmpty) 'answer': q.answer,
          if (q.alternatives.isNotEmpty) 'alternatives': q.alternatives,
          if (q.explanation.isNotEmpty) 'explanation': q.explanation,
          if (q.hint.isNotEmpty) 'hint': q.hint,
          if (q.documentId case final id?) 'document_id': id,
          if (q.icon case final icon?) 'icon': icon,
          if (q.illustrationPrompt.isNotEmpty)
            'illustration_prompt': q.illustrationPrompt,
          if (q.illustrationRef case final ref?) 'illustration_ref': ref,
        },
    ],
  };

  static String encodeString(Quiz quiz) => jsonEncode(encode(quiz));

  static QuizQuestion? _question(Object? raw, int index) {
    final json = studyJsonObject(raw);
    if (json == null) return null;
    final prompt = studyJsonText(json, _promptKeys, max: QuizLimits.question);
    if (prompt.isEmpty) return null;
    final options = _options(json);
    final answer = studyJsonText(json, _answerKeys, max: QuizLimits.answer);
    final declared = _type(studyJsonText(json, const ['type', 'tipo']));

    // El tipo: el que dice, si se puede contestar así; si no, el que se
    // deduce de lo que trae.
    final correct = options.where((o) => o.correct).length;
    final QuizQuestionType type;
    if (options.length >= 2 &&
        correct >= 1 &&
        (declared == null || declared.hasOptions)) {
      type = correct > 1
          ? QuizQuestionType.multiple
          : declared ?? QuizQuestionType.single;
    } else if (answer.isNotEmpty) {
      type = declared == QuizQuestionType.fillBlank || _blanks.hasMatch(prompt)
          ? QuizQuestionType.fillBlank
          : QuizQuestionType.shortAnswer;
    } else {
      return null;
    }

    final id = studyJsonText(json, const ['id'], max: 40);
    final documentId = studyJsonText(json, const ['document_id'], max: 200);
    final icon = studyJsonText(json, const ['icon', 'icono'], max: 40);
    return QuizQuestion(
      id: id.isEmpty ? 'q${index + 1}' : id,
      type: type,
      prompt: type == QuizQuestionType.fillBlank ? _withBlank(prompt) : prompt,
      options: type.hasOptions ? options : const [],
      answer: type.isTyped ? answer : '',
      alternatives: type == QuizQuestionType.fillBlank
          ? studyJsonTexts(json, _alternativesKeys)
          : const [],
      explanation: studyJsonText(
        json,
        _explanationKeys,
        max: QuizLimits.explanation,
      ),
      hint: studyJsonText(json, const ['hint', 'pista'], max: QuizLimits.hint),
      sourceHint: studyJsonText(json, const [
        'source',
        'fuente',
        'documento',
      ], max: QuizLimits.title),
      documentId: documentId.isEmpty ? null : documentId,
      icon: icon.isEmpty ? null : icon,
      illustrationPrompt: studyJsonText(json, const [
        'illustration_prompt',
        'illustration',
        'ilustracion',
        'image_prompt',
      ], max: QuizLimits.prompt),
      // Un mazo de antes guardaba la imagen adentro (`image`): no se lee,
      // y su lugar lleva el dibujo de la app.
      illustrationRef: _blankOrNull(
        studyJsonText(json, const ['illustration_ref'], max: 1024),
      ),
    );
  }

  /// Las opciones, como objetos `{texto, correcta, explicacion}` o como
  /// textos sueltos con la correcta dicha aparte (`"correcta": "B"`, `2` o
  /// el texto mismo).
  static List<QuizOption> _options(Map<String, Object?> json) {
    final raw = studyJsonList(json, _optionsKeys);
    final elsewhere = studyJsonPick(json, const [
      'correct',
      'correcta',
      'correct_option',
      'opcion_correcta',
      'correct_answer',
      'respuesta_correcta',
      'answer',
      'respuesta',
    ]);
    final marked = <int>{
      for (final value in elsewhere is List ? elsewhere : [elsewhere])
        ?_indexOf(value, raw),
    };
    final options = <QuizOption>[];
    final seen = <String>{};
    for (final (i, item) in raw.indexed) {
      final QuizOption option;
      if (item is String || item is num) {
        final text = clampStudyText(_withoutLetter('$item'), QuizLimits.option);
        option = QuizOption(text: text, correct: marked.contains(i));
      } else if (studyJsonObject(item) case final map?) {
        final text = _withoutLetter(
          studyJsonText(map, _optionTextKeys, max: QuizLimits.option),
        );
        option = QuizOption(
          text: text,
          correct: studyJsonBool(map, _correctKeys) ?? marked.contains(i),
          explanation: studyJsonText(
            map,
            _explanationKeys,
            max: QuizLimits.explanation,
          ),
        );
      } else {
        continue;
      }
      if (option.text.isEmpty) continue;
      if (!seen.add(flashcardRejectionFingerprint(option.text))) continue;
      options.add(option);
      if (options.length == QuizLimits.options) break;
    }
    return options;
  }

  /// El lugar de la opción que dice [value] —una letra, un número desde 1 o
  /// su texto—, o `null`.
  static int? _indexOf(Object? value, List<Object?> options) {
    if (value is num) {
      final i = value.toInt() - 1;
      return i >= 0 && i < options.length ? i : null;
    }
    if (value is! String) return null;
    final text = value.trim();
    final letter = RegExp(r'^([A-Fa-f])[\).:]?$').firstMatch(text);
    if (letter != null) {
      final i = letter.group(1)!.toUpperCase().codeUnitAt(0) - 65;
      return i < options.length ? i : null;
    }
    final wanted = flashcardRejectionFingerprint(_withoutLetter(text));
    for (final (i, option) in options.indexed) {
      final map = studyJsonObject(option);
      final optionText = option is String
          ? option
          : map == null
          ? ''
          : studyJsonText(map, _optionTextKeys);
      if (flashcardRejectionFingerprint(_withoutLetter(optionText)) == wanted) {
        return i;
      }
    }
    return null;
  }

  /// Sin la letra que a veces le pone la IA adelante: «B) Roma» → «Roma».
  static String _withoutLetter(String text) =>
      text.trim().replaceFirst(RegExp(r'^[A-Fa-f][\).:]\s+'), '');

  static QuizQuestionType? _type(String raw) {
    final key = studyJsonKey(raw);
    if (key.isEmpty) return null;
    if (QuizQuestionType.fromStorageKey(raw.trim()) case final type?) {
      return type;
    }
    if (key.contains('multip') && !key.contains('choice')) {
      return QuizQuestionType.multiple;
    }
    if (key.contains('seleccion') ||
        key.contains('select') ||
        key.contains('varias') ||
        key.contains('checkbox')) {
      return QuizQuestionType.multiple;
    }
    if (key.contains('complet') ||
        key.contains('blank') ||
        key.contains('cloze') ||
        key.contains('hueco') ||
        key.contains('espacio') ||
        key.contains('fill')) {
      return QuizQuestionType.fillBlank;
    }
    if (key.contains('breve') ||
        key.contains('short') ||
        key.contains('abierta') ||
        key.contains('open') ||
        key.contains('desarrollo') ||
        key.contains('libre')) {
      return QuizQuestionType.shortAnswer;
    }
    if (key.contains('unica') ||
        key.contains('single') ||
        key.contains('choice') ||
        key.contains('opcion') ||
        key.contains('test')) {
      return QuizQuestionType.single;
    }
    return null;
  }

  /// La pregunta de completar con su espacio dicho siempre igual
  /// ([kQuizBlank]); si no traía ninguno, al final.
  static String _withBlank(String prompt) {
    if (_blanks.hasMatch(prompt)) {
      return prompt.replaceFirst(_blanks, kQuizBlank);
    }
    return '$prompt $kQuizBlank';
  }

  /// Cómo escribe la IA un espacio para completar: guiones bajos, `[...]`,
  /// puntos suspensivos de más.
  static final _blanks = RegExp(r'_{3,}|\[\s*\.{3}\s*\]|\.{4,}|…{2,}');

  static Object? _decodeText(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }
}

/// [options] mezcladas de forma estable con [seed]: siempre el mismo orden
/// para la misma pregunta. La IA tiende a poner la correcta primero.
List<QuizOption> shuffleQuizOptions(List<QuizOption> options, int seed) =>
    List.of(options)..shuffle(math.Random(seed));

String? _blankOrNull(String text) => text.isEmpty ? null : text;
