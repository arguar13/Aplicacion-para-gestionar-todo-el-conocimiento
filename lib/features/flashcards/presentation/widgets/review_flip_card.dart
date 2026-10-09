import 'dart:math' as math;

import 'package:flutter/material.dart';

/// La tarjeta de repaso, que se da vuelta (F31, ola 2): de [front] a [back]
/// con un giro sobre su eje vertical, y de vuelta si [showBack] cambia otra
/// vez.
///
/// Dibuja la caja de la tarjeta —fondo, borde, esquinas y altura mínima—;
/// quien la usa pone solo el contenido de cada cara. Se queda en la cara en que
/// nació (sin animar) si arranca con [showBack] verdadero, que es lo que pasa
/// al reconstruirse una tarjeta que ya estaba revelada.
///
/// Con las animaciones del sistema apagadas (accesibilidad) la vuelta es
/// instantánea.
class ReviewFlipCard extends StatefulWidget {
  const ReviewFlipCard({
    required this.showBack,
    required this.front,
    required this.back,
    this.onTap,
    super.key,
  });

  /// Si se ve la cara de atrás.
  final bool showBack;

  final Widget front;
  final Widget back;

  /// Al tocar la tarjeta (revelar la respuesta).
  final VoidCallback? onTap;

  /// Cuánto dura el giro.
  static const flipDuration = Duration(milliseconds: 380);

  @override
  State<ReviewFlipCard> createState() => _ReviewFlipCardState();
}

class _ReviewFlipCardState extends State<ReviewFlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ReviewFlipCard.flipDuration,
    value: widget.showBack ? 1 : 0,
  );
  late final Animation<double> _turn = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Con las animaciones apagadas, el giro se resuelve de una vez.
    _controller.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : ReviewFlipCard.flipDuration;
  }

  @override
  void didUpdateWidget(ReviewFlipCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showBack == oldWidget.showBack) return;
    if (widget.showBack) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _turn,
        builder: (context, _) {
          final turn = _turn.value;
          // Pasada la mitad del giro la tarjeta está de canto: ahí se cambia
          // de cara. La de atrás se dibuja espejada (porque la caja ya giró
          // media vuelta) y se vuelve a espejar para que se lea derecha.
          final showingBack = turn > 0.5;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateY(turn * math.pi),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 200),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              alignment: Alignment.center,
              child: showingBack
                  ? Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.rotationY(math.pi),
                      child: widget.back,
                    )
                  : widget.front,
            ),
          );
        },
      ),
    );
  }
}
