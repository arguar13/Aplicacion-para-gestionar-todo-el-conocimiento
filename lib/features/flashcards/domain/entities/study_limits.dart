import 'package:meta/meta.dart';

/// Cuántas tarjetas se estudian como mucho por día de estudio (F31, decisión
/// 69).
///
/// Dos topes, como en Anki:
/// - [newPerDay]: tarjetas NUEVAS que se empiezan a aprender (20 por defecto).
/// - [reviewsPerDay]: repasos de tarjetas ya aprendidas (200 por defecto).
///
/// Lo que se aprende y reaprende en pasos de minutos NO tiene tope: una
/// tarjeta que ya se empezó se termina de aprender aunque haya pasado el límite
/// de nuevas.
///
/// Son GLOBALES, no por mazo. El plan hablaba de «por mazo», pero los mazos de
/// Sinapsis son recortes dinámicos (un tema, una etiqueta, un cuaderno): una
/// misma tarjeta cae en varios a la vez, y un tope por recorte permitiría
/// pasarse del total con solo cambiar de recorte. El tope es de TODO lo que se
/// estudia en el día, venga del recorte que venga, y elegir un recorte solo
/// filtra qué entra dentro de ese tope.
@immutable
class StudyLimits {
  const StudyLimits({
    this.newPerDay = defaultNewPerDay,
    this.reviewsPerDay = defaultReviewsPerDay,
  }) : assert(newPerDay >= 0 && newPerDay <= maxPerDay, 'Fuera de rango'),
       assert(
         reviewsPerDay >= 0 && reviewsPerDay <= maxPerDay,
         'Fuera de rango',
       );

  /// Lo que viene de fábrica: 20 nuevas por día.
  static const defaultNewPerDay = 20;

  /// Lo que viene de fábrica: 200 repasos por día.
  static const defaultReviewsPerDay = 200;

  /// El tope más alto que se acepta de cada uno: en la práctica, «sin límite».
  static const maxPerDay = 9999;

  final int newPerDay;
  final int reviewsPerDay;

  /// Cuántas nuevas quedan por hacer si ya se hicieron [doneToday].
  int newLeft(int doneToday) => _left(newPerDay, doneToday);

  /// Cuántos repasos quedan por hacer si ya se hicieron [doneToday].
  int reviewsLeft(int doneToday) => _left(reviewsPerDay, doneToday);

  static int _left(int limit, int done) => limit > done ? limit - done : 0;

  /// Estos mismos topes, más generosos por hoy: «estudiar más» (Anki lo llama
  /// ampliar el límite de hoy). No cambia lo guardado: se le pasa a la cola
  /// solo por esta sesión.
  StudyLimits extendedBy({int newCards = 0, int reviews = 0}) => StudyLimits(
    newPerDay: _clamp(newPerDay + newCards),
    reviewsPerDay: _clamp(reviewsPerDay + reviews),
  );

  StudyLimits copyWith({int? newPerDay, int? reviewsPerDay}) => StudyLimits(
    newPerDay: _clamp(newPerDay ?? this.newPerDay),
    reviewsPerDay: _clamp(reviewsPerDay ?? this.reviewsPerDay),
  );

  static int _clamp(int value) => value.clamp(0, maxPerDay);

  @override
  bool operator ==(Object other) =>
      other is StudyLimits &&
      other.newPerDay == newPerDay &&
      other.reviewsPerDay == reviewsPerDay;

  @override
  int get hashCode => Object.hash(newPerDay, reviewsPerDay);

  @override
  String toString() =>
      'StudyLimits(nuevas: $newPerDay, repasos: $reviewsPerDay)';
}
