import 'package:flutter/material.dart';

/// Hacia dónde se soltó una tarjeta.
enum SwipeDirection { left, right, up }

/// Una tarjeta que se arrastra: a la izquierda, a la derecha o hacia arriba, y
/// al soltarla más allá del umbral decide.
///
/// Solo esos tres sentidos significan algo: arrastrar hacia abajo no hace nada
/// y la tarjeta vuelve a su lugar. Lo mismo si se suelta antes del umbral: no
/// se decide por un roce. Mientras se arrastra, [hints] muestra qué pasaría al
/// soltar en cada sentido, con más fuerza cuanto más cerca del umbral.
///
/// No decide nada por sí sola: avisa con [onSwipe] y quien la aloja actúa. Si
/// esa acción no saca a la tarjeta de la pantalla —falló—, vuelve a su lugar.
class SwipeCard extends StatefulWidget {
  const SwipeCard({
    required this.child,
    required this.onSwipe,
    required this.hints,
    this.threshold = 96,
    super.key,
  });

  final Widget child;
  final ValueChanged<SwipeDirection> onSwipe;

  /// El texto y el color que se muestran para cada sentido mientras se
  /// arrastra.
  final Map<SwipeDirection, ({String label, Color color})> hints;

  /// Cuánto hay que arrastrar, en píxeles, para que suelte y decida.
  final double threshold;

  @override
  State<SwipeCard> createState() => _SwipeCardState();
}

class _SwipeCardState extends State<SwipeCard>
    with SingleTickerProviderStateMixin {
  /// Cuánto tiene que ir de rápido un empujón, en píxeles por segundo, para
  /// decidir sin llegar al umbral.
  static const _flingSpeed = 700.0;

  /// Lo mínimo que hay que haber arrastrado para que un empujón cuente.
  static const _flingMinDistance = 32.0;

  late final AnimationController _springBack =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 180),
      )..addListener(() {
        final t = Curves.easeOutCubic.transform(_springBack.value);
        setState(() => _offset = Offset.lerp(_returnFrom, Offset.zero, t)!);
      });

  Offset _offset = Offset.zero;

  // Desde dónde vuelve la tarjeta: fija durante todo el regreso.
  Offset _returnFrom = Offset.zero;

  @override
  void dispose() {
    _springBack.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails details) => _springBack.stop();

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() => _offset += details.delta);
  }

  void _onPanEnd(DragEndDetails details) {
    final direction = _decide(_offset, details.velocity.pixelsPerSecond);
    if (direction != null) {
      widget.onSwipe(direction);
    }
    _goBack();
  }

  /// Vuelve a su lugar. Si la acción sacó a la tarjeta, ya no se ve: si
  /// falló, es lo que hace que no quede torcida.
  void _goBack() {
    _returnFrom = _offset;
    _springBack
      ..reset()
      ..forward();
  }

  SwipeDirection? _decide(Offset offset, Offset velocity) {
    final horizontal = offset.dx.abs() >= offset.dy.abs();

    bool reaches(double distance, double speed) =>
        distance >= widget.threshold ||
        (distance >= _flingMinDistance && speed >= _flingSpeed);

    if (horizontal) {
      if (offset.dx < 0 && reaches(-offset.dx, -velocity.dx)) {
        return SwipeDirection.left;
      }
      if (offset.dx > 0 && reaches(offset.dx, velocity.dx)) {
        return SwipeDirection.right;
      }
      return null;
    }
    if (offset.dy < 0 && reaches(-offset.dy, -velocity.dy)) {
      return SwipeDirection.up;
    }
    return null;
  }

  /// Qué sentido se está insinuando y con qué fuerza, de 0 a 1.
  ({SwipeDirection direction, double strength})? get _leaning {
    final dx = _offset.dx;
    final dy = _offset.dy;
    if (dx.abs() >= dy.abs()) {
      if (dx == 0) return null;
      return (
        direction: dx < 0 ? SwipeDirection.left : SwipeDirection.right,
        strength: (dx.abs() / widget.threshold).clamp(0, 1),
      );
    }
    if (dy < 0) {
      return (
        direction: SwipeDirection.up,
        strength: (-dy / widget.threshold).clamp(0, 1),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final leaning = _leaning;
    final hint = leaning == null ? null : widget.hints[leaning.direction];

    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: Transform.translate(
        offset: _offset,
        child: Transform.rotate(
          angle: _offset.dx / 1600,
          child: Stack(
            children: [
              widget.child,
              if (hint != null && leaning != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: leaning.strength,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: hint.color, width: 3),
                          color: hint.color.withValues(alpha: 0.10),
                        ),
                        child: Align(
                          alignment: switch (leaning.direction) {
                            SwipeDirection.left => Alignment.topRight,
                            SwipeDirection.right => Alignment.topLeft,
                            SwipeDirection.up => Alignment.bottomCenter,
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              hint.label,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: hint.color,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
