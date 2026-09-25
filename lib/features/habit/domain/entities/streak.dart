/// La racha del usuario (F17, D6): cuántos días seguidos hubo alguna
/// actividad que cuenta, contando la gracia.
class Streak {
  const Streak({required this.days, required this.activeToday});

  /// Cuántos días seguidos, contando los de gracia como si hubieran
  /// tenido actividad. 0 si ni ayer ni hoy hubo nada, y ya se gastó toda
  /// la gracia disponible antes de eso.
  final int days;

  /// Si HOY ya hubo alguna actividad que cuenta —no hace falta hacer más
  /// nada para mantener la racha—.
  final bool activeToday;
}
