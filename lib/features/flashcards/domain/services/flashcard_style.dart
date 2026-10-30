import 'package:flutter/foundation.dart';

/// Qué tan exigentes se piden las tarjetas: los tres de la hoja de «Tarjetas
/// didácticas» (F43).
enum FlashcardDifficulty { easy, medium, hard }

/// Cuántas tarjetas, al lado de las que corresponden por el largo del texto
/// (`flashcardTargetFor`): los «Menos · Estándar · Más» de la hoja.
enum FlashcardAmount { fewer, standard, more }

/// Cómo se piden las tarjetas de cada documento cuando la persona eligió
/// (F43, M18): lo de la hoja de «Tarjetas didácticas» que vale también para
/// «Para cada documento» —el idioma, la dificultad, el tema y cuántas—.
///
/// [plain] es lo de siempre: lo que hace la IA que organiza sola (F27), lo
/// que pide «Llenar con IA» de un cuaderno (F30) y lo que se pedía con el ✨
/// de Repasar. Con él, el pedido al modelo es el mismo de antes, letra por
/// letra.
///
/// El idioma, la dificultad y el tema los dice el generador
/// (`LanguageModelTasks.flashcardsWith`); cuántas, quien las pide
/// (`AutoFlashcardsStep`), porque sale del largo de cada texto.
@immutable
class FlashcardStyle {
  const FlashcardStyle({
    this.languageCode = 'es',
    this.difficulty,
    this.topic = '',
    this.amount = FlashcardAmount.standard,
  });

  /// Lo de siempre: en español, sin dificultad ni tema, las que da el largo.
  static const plain = FlashcardStyle();

  /// En qué idioma van la pregunta y la respuesta (`es`, `en`, `pt`…). La
  /// frase de la que sale cada una va siempre en el del texto: es una cita.
  final String languageCode;

  /// `null` es «la de siempre»: no se le dice nada al modelo.
  final FlashcardDifficulty? difficulty;

  /// En qué concentrarse; vacío, en lo más importante del texto.
  final String topic;

  final FlashcardAmount amount;

  /// Si el idioma es el español, con o sin región (`es`, `es-AR`).
  bool get isSpanish => languageCode.split(RegExp('[-_]')).first == 'es';

  /// Si el pedido al modelo dice algo más que el de siempre: otro idioma,
  /// una dificultad o un tema. Cuántas no cambia el pedido.
  bool get changesPrompt =>
      !isSpanish || difficulty != null || topic.trim().isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is FlashcardStyle &&
      other.languageCode == languageCode &&
      other.difficulty == difficulty &&
      other.topic == topic &&
      other.amount == amount;

  @override
  int get hashCode => Object.hash(languageCode, difficulty, topic, amount);

  @override
  String toString() =>
      'FlashcardStyle($languageCode, ${difficulty?.name}, «$topic», '
      '${amount.name})';
}
