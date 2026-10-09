import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/review_grade_row.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Qué calificación da deslizar [offset] la tarjeta, o `null` si todavía no se
/// movió: derecha «Bien», izquierda «De nuevo», arriba «Fácil», abajo
/// «Difícil». Manda el eje en el que más se movió.
ReviewGrade? reviewGradeForSwipe(Offset offset) {
  if (offset == Offset.zero) return null;
  if (offset.dx.abs() >= offset.dy.abs()) {
    return offset.dx > 0 ? ReviewGrade.good : ReviewGrade.again;
  }
  return offset.dy < 0 ? ReviewGrade.easy : ReviewGrade.hard;
}

/// Deslizar la tarjeta para calificarla (F31, ola 2): mientras se arrastra, la
/// tarjeta sigue al dedo y se tiñe del color de la calificación con su nombre;
/// pasado un umbral vibra una vez (queda «armada») y al soltar se va hacia ese
/// lado y se califica. Si se suelta antes de armarla, vuelve a su lugar.
///
/// Es un atajo: los cuatro botones siguen, y para quien no puede arrastrar,
/// cada calificación también es una acción de accesibilidad de la tarjeta.
class ReviewSwipeCard extends StatefulWidget {
  const ReviewSwipeCard({
    required this.enabled,
    required this.onSwiped,
    required this.child,
    super.key,
  });

  /// Si se puede calificar deslizando (con la respuesta a la vista y sin otra
  /// respuesta en camino).
  final bool enabled;

  final ValueChanged<ReviewGrade> onSwiped;
  final Widget child;

  /// Lo que hay que arrastrar, como máximo, para armar la calificación; en
  /// una tarjeta angosta es el 30 % del ancho.
  static const maxThreshold = 120.0;
  static const minThreshold = 64.0;

  @override
  State<ReviewSwipeCard> createState() => _ReviewSwipeCardState();
}

class _ReviewSwipeCardState extends State<ReviewSwipeCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  Animation<Offset>? _animation;

  /// Dónde está la tarjeta respecto de su lugar.
  Offset _offset = Offset.zero;

  /// La calificación que se aplicaría si se soltara ahora: `null` mientras no
  /// se pasó el umbral.
  ReviewGrade? _armed;

  /// Si ya se soltó y la tarjeta se está yendo: no admite otro gesto hasta que
  /// vuelva o se la reemplace.
  var _leaving = false;
  var _width = 0.0;

  double get _threshold => math.max(
    ReviewSwipeCard.minThreshold,
    math.min(_width * 0.3, ReviewSwipeCard.maxThreshold),
  );

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final animation = _animation;
      if (animation != null) setState(() => _offset = animation.value);
    });
  }

  @override
  void didUpdateWidget(ReviewSwipeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Se soltó y la calificación no se pudo guardar: la tarjeta vuelve.
    if (_leaving && widget.enabled && !oldWidget.enabled) {
      _leaving = false;
      _armed = null;
      _animateTo(Offset.zero, const Duration(milliseconds: 220));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Cuánto avanzó hacia su calificación, de 0 a 1.
  double get _progress {
    final main = _offset.dx.abs() >= _offset.dy.abs()
        ? _offset.dx.abs()
        : _offset.dy.abs();
    return (main / _threshold).clamp(0.0, 1.0);
  }

  void _animateTo(Offset target, Duration duration, {VoidCallback? then}) {
    _controller.stop();
    _animation = Tween<Offset>(
      begin: _offset,
      end: target,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.duration = _reduceMotion ? Duration.zero : duration;
    unawaited(
      _controller.forward(from: 0).then((_) {
        if (mounted && then != null) then();
      }),
    );
  }

  void _onUpdate(DragUpdateDetails details) {
    if (!widget.enabled || _leaving) return;
    setState(() {
      _offset += details.delta;
      final armed = _progress >= 1 ? reviewGradeForSwipe(_offset) : null;
      // Vibra una vez al armarla, y otra al cambiar de calificación.
      if (armed != null && armed != _armed) {
        unawaited(HapticFeedback.selectionClick());
      }
      _armed = armed;
    });
  }

  void _onEnd(DragEndDetails details) {
    if (!widget.enabled || _leaving) return;
    var grade = _armed;
    // Un gesto rápido y decidido también cuenta, aunque no llegue al umbral.
    if (grade == null &&
        details.velocity.pixelsPerSecond.distance > 900 &&
        _progress > 0.4) {
      grade = reviewGradeForSwipe(_offset);
    }
    if (grade == null) {
      setState(() => _armed = null);
      _animateTo(Offset.zero, const Duration(milliseconds: 220));
      return;
    }
    final swiped = grade;
    _leaving = true;
    unawaited(HapticFeedback.mediumImpact());
    final direction = _offset / _offset.distance;
    _animateTo(
      _offset + direction * (_width + 80),
      const Duration(milliseconds: 160),
      then: () {
        widget.onSwiped(swiped);
        // Si nadie tomó la calificación (la pantalla sigue permitiendo
        // deslizar al próximo cuadro), la tarjeta no puede quedar fuera.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _leaving && widget.enabled) {
            _leaving = false;
            _armed = null;
            _animateTo(Offset.zero, const Duration(milliseconds: 220));
          }
        });
      },
    );
  }

  void _onCancel() {
    if (_leaving) return;
    setState(() => _armed = null);
    _animateTo(Offset.zero, const Duration(milliseconds: 220));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final progress = _progress;
    final graded = reviewGradeForSwipe(_offset);

    final card = LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        return Transform.translate(
          offset: _offset,
          child: Transform.rotate(
            angle: _width == 0 ? 0 : (_offset.dx / _width) * 0.18,
            child: Stack(
              children: [
                widget.child,
                if (graded != null && progress > 0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: _SwipeVeil(
                        key: const Key('review-swipe-veil'),
                        grade: graded,
                        strength: progress,
                        armed: _armed != null,
                        label: reviewGradeLabel(l10n, graded),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );

    // Siempre con la misma forma, deslice o no: si el árbol cambiara al
    // habilitarse, la tarjeta de adentro se reharía y perdería la vuelta que
    // estaba haciendo.
    final enabled = widget.enabled;
    return Semantics(
      // Para quien no puede arrastrar: la misma calificación como acción.
      customSemanticsActions: {
        if (enabled)
          for (final grade in ReviewGrade.values)
            CustomSemanticsAction(label: reviewGradeLabel(l10n, grade)): () =>
                widget.onSwiped(grade),
      },
      child: GestureDetector(
        onPanUpdate: enabled ? _onUpdate : null,
        onPanEnd: enabled ? _onEnd : null,
        onPanCancel: enabled ? _onCancel : null,
        child: card,
      ),
    );
  }
}

/// El velo de color que va tiñendo la tarjeta al arrastrarla: del color de la
/// calificación, con su nombre y su ícono. Más opaco cuanto más cerca de
/// armarla; con la calificación armada, el ícono se agranda.
class _SwipeVeil extends StatelessWidget {
  const _SwipeVeil({
    required this.grade,
    required this.strength,
    required this.armed,
    required this.label,
    super.key,
  });

  final ReviewGrade grade;
  final double strength;
  final bool armed;
  final String label;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = reviewGradeColors(
      Theme.of(context).colorScheme,
      grade,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ColoredBox(
        color: background.withValues(alpha: 0.85 * strength),
        child: Opacity(
          opacity: strength,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: armed ? 1.25 : 1,
                  duration: const Duration(milliseconds: 120),
                  child: Icon(
                    reviewGradeIcon(grade),
                    size: 44,
                    color: foreground,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
