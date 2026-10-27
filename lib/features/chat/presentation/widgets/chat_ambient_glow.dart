import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cuánto dura una respiración del brillo del chat vacío —inspirar y
/// exhalar— (F42): lenta, para que se sienta vivo sin distraer.
const kChatGlowBreath = Duration(seconds: 12);

/// Cuántas veces respira el brillo cada vez que aparece el chat vacío.
const kChatGlowBreaths = 3;

/// Cuántas veces respira el brillo al aparecer (F42); 0, quieto.
///
/// Es finito a propósito: una animación que no termina hace que el motor
/// dibuje 60 cuadros por segundo para siempre aunque nadie toque nada —con el
/// chat abierto sobre la mesa, batería que se va—. Tres respiraciones son el
/// rato en que se decide qué preguntar; después queda quieto, exhalado, y
/// vuelve a respirar la próxima vez que aparezca el vacío.
///
/// Un provider para que las pruebas lo dejen quieto: con el reloj simulado,
/// cada `pumpAndSettle` sobre el chat vacío pasaría medio minuto de cuadros.
final chatGlowBreathsProvider = Provider<int>((ref) => kChatGlowBreaths);

/// El fondo del chat vacío (F42): un brillo suave con los colores del tema,
/// que sube desde abajo —donde está el campo— y respira despacio.
///
/// **Barato a propósito.** El degradé se pinta una sola vez, en su propia
/// capa ([RepaintBoundary]); lo que respira es la opacidad y la escala de esa
/// capa ([FadeTransition], [ScaleTransition]), que el motor resuelve al
/// componer el cuadro sin volver a pintar nada. Con «sin animaciones» del
/// sistema queda quieto —y sin reloj andando—; tapado por otra pantalla, el
/// `TickerMode` del `Navigator` lo frena solo.
///
/// Se adapta a los nueve temas porque no tiene colores propios: usa el
/// primario y el terciario del tema, más presentes en los oscuros —donde un
/// brillo se ve— que en los claros, donde apenas tiñe el papel. Con «alto
/// contraste» del sistema no se dibuja: el fondo queda liso.
class ChatAmbientGlow extends ConsumerStatefulWidget {
  const ChatAmbientGlow({super.key});

  @override
  ConsumerState<ChatAmbientGlow> createState() => _ChatAmbientGlowState();
}

class _ChatAmbientGlowState extends ConsumerState<ChatAmbientGlow>
    with SingleTickerProviderStateMixin {
  late final int _breaths = ref.read(chatGlowBreathsProvider);
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: kChatGlowBreath * math.max(_breaths, 1),
  );
  // De 0 (exhalado) a 1 (inspirado) y de vuelta, [_breaths] veces.
  late final Animatable<double> _breathing = _Breathing(_breaths);
  late final Animation<double> _opacity = _breath.drive(
    Tween<double>(begin: 0.6, end: 1).chain(_breathing),
  );
  late final Animation<double> _scale = _breath.drive(
    Tween<double>(begin: 1, end: 1.08).chain(_breathing),
  );
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      // Quieto, exhalado: el brillo se ve, pero no se mueve.
      _breath
        ..stop()
        ..value = 1;
    } else if (!_started && _breaths > 0) {
      _started = true;
      _breath.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.highContrastOf(context)) return const SizedBox.expand();
    final theme = Theme.of(context);
    final glow = RepaintBoundary(
      child: CustomPaint(
        key: const Key('chat-ambient-glow'),
        size: Size.infinite,
        painter: ChatGlowPainter(
          scheme: theme.colorScheme,
          dark: theme.brightness == Brightness.dark,
        ),
      ),
    );
    return IgnorePointer(
      child: ExcludeSemantics(
        child: FadeTransition(
          opacity: _opacity,
          child: ScaleTransition(
            scale: _scale,
            alignment: Alignment.bottomCenter,
            child: glow,
          ),
        ),
      ),
    );
  }
}

/// [breaths] respiraciones a lo largo de la animación: de exhalado (0) a
/// inspirado (1) y de vuelta, con la suavidad de un coseno. Empieza y
/// termina exhalado —por eso no es una `Curve`, que tiene que terminar en 1:
/// el brillo quedaría en su pico en vez de en reposo—.
class _Breathing extends Animatable<double> {
  const _Breathing(this.breaths);

  final int breaths;

  @override
  double transform(double t) => 0.5 - 0.5 * math.cos(2 * math.pi * breaths * t);
}

/// Dos manchas de luz: la grande, del primario, desde abajo al centro; una
/// más chica y tenue, del terciario, arriba a un costado, para que el fondo
/// no sea un solo color.
@visibleForTesting
class ChatGlowPainter extends CustomPainter {
  const ChatGlowPainter({required this.scheme, required this.dark});

  final ColorScheme scheme;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final reach = size.longestSide;
    void spot(Offset center, double radius, Color color, double alpha) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: alpha * 0.35),
              color.withValues(alpha: 0),
            ],
            stops: const [0, 0.45, 1],
          ).createShader(rect),
      );
    }

    spot(
      Offset(size.width / 2, size.height * 1.08),
      reach * 0.75,
      scheme.primary,
      dark ? 0.32 : 0.16,
    );
    spot(
      Offset(size.width * 0.12, size.height * 0.08),
      reach * 0.45,
      scheme.tertiary,
      dark ? 0.14 : 0.08,
    );
  }

  @override
  bool shouldRepaint(ChatGlowPainter oldDelegate) =>
      oldDelegate.scheme.primary != scheme.primary ||
      oldDelegate.scheme.tertiary != scheme.tertiary ||
      oldDelegate.dark != dark;
}
