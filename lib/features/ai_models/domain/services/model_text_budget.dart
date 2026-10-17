import 'dart:math' as math;

import 'package:meta/meta.dart';

/// Cuánto texto se le da al modelo de lenguaje elegido por pedido (F32): un
/// texto largo —un libro, la transcripción de un video de horas— se lee por
/// partes de [partChars], y de cada parte se le piden a lo sumo
/// [maxDraftsPerCall] tarjetas.
///
/// Con Gemma, que lee 2048 tokens para todo, son partes de 3000 caracteres y
/// cuatro tarjetas: lo medido en F27 y F30. Un modelo en la nube lee decenas
/// o cientos de miles de tokens: un capítulo entra entero, y la tarjeta ve el
/// contexto en vez de un pedazo suelto.
@immutable
class ModelTextBudget {
  const ModelTextBudget({
    required this.partChars,
    required this.maxDraftsPerCall,
  });

  /// Hasta cuántos caracteres del texto lee por pedido.
  final int partChars;

  /// Cuántas tarjetas se le piden, como mucho, por pedido: más que esto no
  /// entra en su respuesta junto con la parte.
  final int maxDraftsPerCall;

  @override
  bool operator ==(Object other) =>
      other is ModelTextBudget &&
      other.partChars == partChars &&
      other.maxDraftsPerCall == maxDraftsPerCall;

  @override
  int get hashCode => Object.hash(partChars, maxDraftsPerCall);

  @override
  String toString() => 'ModelTextBudget($partChars, $maxDraftsPerCall)';
}

/// Lo de una ventana chica como la de Gemma (2048 tokens). 3000 caracteres
/// son ~860 tokens —en español, unos 3,5 caracteres por token—, más ~150 de
/// instrucciones y ~90 por tarjeta de respuesta: con cuatro, entra con lugar
/// de sobra.
const kSmallWindowTextBudget = ModelTextBudget(
  partChars: 3000,
  maxDraftsPerCall: 4,
);

/// Desde cuántos tokens de ventana deja de ser chica: lo que entra en una
/// ventana menor se reparte como en Gemma.
const kLargeWindowTokens = 16000;

/// Lo más largo que se manda de una vez aunque la ventana dé para más: unos
/// 17.000 tokens, un capítulo largo. Más que esto gasta de golpe el tope
/// por minuto de la capa gratuita y, en un libro, deja menos partes —menos
/// lugares del texto de donde salen las tarjetas—.
const kMaxPartChars = 60000;

/// Cuántas tarjetas por pedido con una ventana grande: ocho con su cita
/// caben holgadas en la respuesta (`draftsReplyTokens`).
const kLargeWindowDraftsPerCall = 8;

/// En cuántas partes se reparte la ventana: la parte usa un cuarto, y el
/// resto queda para la instrucción, la respuesta y lo que el tokenizador
/// cuente de más.
const _windowShareForPart = 4;

/// Caracteres por token en español, la cuenta con que se reparte: el modelo
/// cuenta de verdad al mandar.
const _charsPerToken = 3.5;

/// El presupuesto para un modelo que lee [contextTokens] de una vez.
ModelTextBudget textBudgetFor(int contextTokens) {
  if (contextTokens < kLargeWindowTokens) return kSmallWindowTextBudget;
  final fits = (contextTokens / _windowShareForPart * _charsPerToken).floor();
  return ModelTextBudget(
    partChars: math.min(kMaxPartChars, fits),
    maxDraftsPerCall: kLargeWindowDraftsPerCall,
  );
}
