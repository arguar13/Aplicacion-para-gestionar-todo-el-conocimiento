import 'dart:ui';

/// Cuánto dura el cambio de altura del lienzo (F44, paso 2): corto, para que
/// se entienda de dónde sale lo nuevo sin hacer esperar.
const kCanvasMotionDuration = Duration(milliseconds: 360);

/// Cuánto dura recoger lo que se miraba al subir una altura.
const kCanvasCollapseDuration = Duration(milliseconds: 220);

/// Un movimiento del lienzo entre dos alturas: de dónde sale cada nodo, adónde
/// va y si aparece o se va.
///
/// - **Salir de la burbuja** ([CanvasMotion.emerge]): al entrar en una
///   comunidad o en un tema, lo nuevo nace donde estaba lo que se tocó y se
///   acomoda en su lugar.
/// - **Recoger** ([CanvasMotion.collapse]): al subir, lo que se miraba vuelve
///   a juntarse en su centro y se apaga.
/// - **Aparecer** ([CanvasMotion.fadeIn]): lo nuevo, quieto en su lugar, se
///   enciende.
///
/// Es puro: dice dónde está cada nodo y cuánto se ve a una altura `t` del
/// movimiento, de 0 a 1, ya con la curva puesta.
class CanvasMotion {
  const CanvasMotion._({
    required this.from,
    required this.to,
    required this.fadeOut,
  });

  /// Cada nodo de [to] nace en [origin] y va a su lugar.
  factory CanvasMotion.emerge(Offset origin, Map<String, Offset> to) =>
      CanvasMotion._(
        from: {for (final key in to.keys) key: origin},
        to: to,
        fadeOut: false,
      );

  /// Cada nodo de [positions] va a su centro, y se apaga.
  factory CanvasMotion.collapse(Map<String, Offset> positions) {
    var sum = Offset.zero;
    for (final at in positions.values) {
      sum += at;
    }
    final center = positions.isEmpty ? sum : sum / positions.length.toDouble();
    return CanvasMotion._(
      from: positions,
      to: {for (final key in positions.keys) key: center},
      fadeOut: true,
    );
  }

  /// Cada nodo de [positions] se queda en su lugar y se enciende.
  factory CanvasMotion.fadeIn(Map<String, Offset> positions) =>
      CanvasMotion._(from: positions, to: positions, fadeOut: false);

  final Map<String, Offset> from;
  final Map<String, Offset> to;

  /// Si lo que se mueve se va, en vez de llegar.
  final bool fadeOut;

  /// Dónde está cada nodo a la altura [t] del movimiento.
  Map<String, Offset> positionsAt(double t) => {
    for (final MapEntry(:key, :value) in to.entries)
      key: Offset.lerp(from[key] ?? value, value, t)!,
  };

  /// Cuánto se ve lo que se mueve a la altura [t].
  double opacityAt(double t) => (fadeOut ? 1 - t : t).clamp(0.0, 1.0);
}
