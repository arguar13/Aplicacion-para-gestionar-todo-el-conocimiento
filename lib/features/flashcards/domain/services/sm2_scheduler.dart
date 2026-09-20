import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';

/// El algoritmo SM-2 de Piotr Wozniak (1987), el mismo que usa Anki: a
/// partir de cómo salió un repaso, decide cuántos días esperar hasta el
/// próximo.
///
/// Función pura y sin estado a propósito —recibe la tarjeta, devuelve la
/// tarjeta siguiente— para poder probarla sin una base de datos de por
/// medio: la lógica de cuándo repasar algo no debería depender de que haya
/// una fila real en SQLite.
Flashcard scheduleNext(
  Flashcard card,
  ReviewGrade grade, {
  required DateTime now,
}) {
  final quality = qualityOf(grade);
  final nextEase = _nextEase(card.easeFactor, quality);

  // Quality < 3 (no se recordó, "de nuevo"): SM-2 reinicia la tarjeta como
  // si fuera nueva, sin importar cuánto había crecido el intervalo antes.
  // Es lo que evita que una tarjeta que se olvidó vuelva a aparecer recién
  // en dos meses porque acumuló muchos repasos exitosos en el pasado.
  if (quality < 3) {
    return card.copyWith(
      repetitions: 0,
      intervalDays: 1,
      easeFactor: nextEase,
      dueAt: now.add(const Duration(days: 1)),
      lastReviewedAt: now,
    );
  }

  final nextRepetitions = card.repetitions + 1;
  final nextInterval = switch (nextRepetitions) {
    1 => 1,
    2 => 6,
    // A partir del tercer repaso exitoso seguido, el intervalo anterior se
    // multiplica por el factor de facilidad: es lo que hace que una
    // tarjeta fácil se espacie cada vez más, en vez de crecer siempre al
    // mismo ritmo.
    _ => (card.intervalDays * nextEase).round(),
  };

  return card.copyWith(
    repetitions: nextRepetitions,
    intervalDays: nextInterval,
    easeFactor: nextEase,
    dueAt: now.add(Duration(days: nextInterval)),
    lastReviewedAt: now,
  );
}

/// La calidad de SM-2 (0 a 5) que le corresponde a lo que eligió la persona.
///
/// Pública porque el historial de repasos guarda las dos cosas —el nombre de la
/// nota y el número que usó el algoritmo—, y el número no puede calcularse en
/// otro lado: si esta tabla cambiara, el historial diría otra cosa que el
/// algoritmo.
int qualityOf(ReviewGrade grade) => switch (grade) {
  ReviewGrade.again => 0,
  ReviewGrade.hard => 3,
  ReviewGrade.good => 4,
  ReviewGrade.easy => 5,
};

/// La fórmula original de SM-2, con el piso de 1.3 que el propio algoritmo
/// define: sin él, una racha de tarjetas difíciles podría llevar el factor
/// a valores tan bajos que el intervalo prácticamente dejara de crecer,
/// aunque la tarjeta se estuviera empezando a recordar bien.
double _nextEase(double easeFactor, int quality) {
  final next =
      easeFactor + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02));
  return next < 1.3 ? 1.3 : next;
}
