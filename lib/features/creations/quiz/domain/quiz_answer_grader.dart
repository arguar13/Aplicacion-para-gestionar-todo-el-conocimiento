import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/creations/flashcards/domain/study_item_json.dart';
import 'package:sinapsis/features/creations/quiz/domain/quiz.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

/// Lo que dijo la IA de una respuesta breve.
@immutable
class QuizGrade {
  const QuizGrade({required this.correct, required this.reason});

  final bool correct;

  /// Por qué, en una o dos oraciones.
  final String reason;
}

/// La IA revisa una «Respuesta breve» (F43, paso 8): si lo que la persona
/// escribió dice lo mismo que la respuesta esperada —con otras palabras
/// vale—, y por qué. Va por el mismo pedido de JSON de «Lo creado»
/// ([StructuredWriter]): el modelo elegido, con el turno de la persona, la
/// corrección de una respuesta rota y cancelable.
///
/// Sin un modelo listo ([isAvailable] da `false`), el visor muestra la
/// respuesta esperada y la persona se autocalifica.
class QuizAnswerGrader {
  const QuizAnswerGrader({
    required StructuredWriter Function() writer,
    required LanguageModelStatusCheck Function() readiness,
  }) : _writer = writer,
       _readiness = readiness;

  final StructuredWriter Function() _writer;
  final LanguageModelStatusCheck Function() _readiness;

  /// Lo que se le deja a la respuesta de la IA: un sí o no y una razón.
  static const replyTokens = 260;

  /// Si hay un modelo de lenguaje listo para revisar.
  Future<bool> isAvailable() async {
    try {
      return (await _readiness()()).isReady;
      // Saber si hay modelo no puede tumbar el cuestionario: sin saber, se
      // autocalifica.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return false;
    }
  }

  /// Revisa [typed] para [question], en [languageCode]. Lanza
  /// [CreationCancelledException] si se canceló y [UnreadableStructuredReply]
  /// si la IA no contestó lo pedido.
  Future<QuizGrade> grade({
    required QuizQuestion question,
    required String typed,
    required String languageCode,
    CancellationSignal? cancellation,
  }) {
    final writer = _writer();
    final material = [
      'Pregunta: ${question.prompt}',
      'Respuesta esperada: ${question.answer}',
      if (question.explanation.isNotEmpty)
        'Explicación de la respuesta: ${question.explanation}',
      'Respuesta de la persona: ${typed.trim()}',
    ].join('\n');
    return writer.writeStructured(
      StructuredRequest(
        task:
            'revisar si la respuesta de la persona a la pregunta es correcta: '
            'lo es si dice lo esencial de la respuesta esperada, aunque use '
            'otras palabras o tenga faltas de ortografía; no lo es si le '
            'falta lo esencial, si se equivoca o si no contesta lo que se '
            'pregunta. La razón, en una o dos oraciones, le habla a la '
            'persona y le dice qué le faltó o qué estuvo bien',
        schema: '{"correcta": true, "razon": "…"}',
        material: CreationMaterial(
          mode: CreationMaterialMode.fullText,
          text: material,
          sources: const [],
        ),
        budget: CreationBudget(
          contextTokens: writer.contextTokens,
          reservedOutputTokens: replyTokens,
        ),
        maxOutputTokens: replyTokens,
        parse: parseQuizGrade,
        languageCode: languageCode,
        cancellation: cancellation,
      ),
    );
  }
}

/// Lee lo que contestó la IA al revisar: `{"correcta": bool, "razon": …}`,
/// con tolerancia. Lanza [FormatException] si no dice si está bien.
QuizGrade parseQuizGrade(Object? json) {
  final map = studyJsonObject(json);
  final correct = map == null
      ? null
      : studyJsonBool(map, const [
          'correcta',
          'correct',
          'correcto',
          'is_correct',
          'ok',
          'bien',
        ]);
  if (map == null || correct == null) {
    throw const FormatException('Falta "correcta": true o false.');
  }
  return QuizGrade(
    correct: correct,
    reason: studyJsonText(map, const [
      'razon',
      'reason',
      'explicacion',
      'explanation',
      'porque',
      'feedback',
    ], max: 600),
  );
}
