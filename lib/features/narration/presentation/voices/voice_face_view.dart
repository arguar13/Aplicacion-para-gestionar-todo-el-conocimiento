import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_face.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_profile.dart';

/// La cara de una voz (F47, paso 3, decisión D): un círculo con el degradé de
/// sus dos tonos, su onda abajo y sus iniciales en el medio. Nunca una foto.
///
/// Es la misma en claro y en oscuro —los mismos tonos—, con la luz de cada
/// tema: pastel con letras oscuras en claro, profunda con letras claras en
/// oscuro, siempre con contraste para leer las iniciales. Para el lector de
/// pantalla no dice nada: la voz la nombra su tarjeta.
///
/// Es la que muestra el reproductor del paso 2 («la cara de la voz»), con
/// [VoiceFaceView.of].
class VoiceFaceView extends StatelessWidget {
  const VoiceFaceView({required this.face, this.size = 48, super.key});

  /// La cara de [voice].
  factory VoiceFaceView.of(VoiceProfile voice, {double size = 48, Key? key}) =>
      VoiceFaceView(
        face: VoiceFace.of(voice.id, voice.label),
        size: size,
        key: key,
      );

  final VoiceFace face;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final palette = VoiceFacePalette.of(face, dark: dark);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _FacePainter(face: face, palette: palette),
          child: Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: size * 0.12),
              // La cara mide lo mismo con la letra grande: las iniciales se
              // achican para entrar, no la agrandan.
              child: FittedBox(
                child: Padding(
                  padding: EdgeInsets.all(size * 0.18),
                  child: Text(
                    face.initials,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      color: palette.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: size * 0.36,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Los colores de una cara en un tema.
@immutable
class VoiceFacePalette {
  const VoiceFacePalette._(this.start, this.end, this.wave, this.ink);

  factory VoiceFacePalette.of(VoiceFace face, {required bool dark}) {
    Color tone(double hue, double lightness) =>
        HSLColor.fromAHSL(1, hue, dark ? 0.45 : 0.6, lightness).toColor();
    return VoiceFacePalette._(
      tone(face.hue, dark ? 0.30 : 0.84),
      tone(face.accentHue, dark ? 0.22 : 0.74),
      tone(face.accentHue, dark ? 0.55 : 0.42).withValues(alpha: 0.55),
      dark ? const Color(0xFFF7F7FA) : const Color(0xFF15151C),
    );
  }

  final Color start;
  final Color end;
  final Color wave;

  /// El color de las iniciales.
  final Color ink;
}

class _FacePainter extends CustomPainter {
  const _FacePainter({required this.face, required this.palette});

  final VoiceFace face;
  final VoiceFacePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final angle = face.tilt * 2 * math.pi;
    final direction = Offset(math.cos(angle), math.sin(angle));
    final center = rect.center;
    final radius = size.shortestSide / 2;
    canvas
      ..save()
      ..clipPath(Path()..addOval(rect))
      ..drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment(-direction.dx, -direction.dy),
            end: Alignment(direction.dx, direction.dy),
            colors: [palette.start, palette.end],
          ).createShader(rect),
      );

    // La onda: barras redondeadas abajo, del alto que dice la cara.
    final bars = face.wave.length;
    final band = size.width * 0.62;
    final step = band / bars;
    final barWidth = step * 0.55;
    final base = center.dy + radius * 0.72;
    final maxHeight = radius * 0.5;
    final paint = Paint()..color = palette.wave;
    for (var i = 0; i < bars; i++) {
      final height = maxHeight * face.wave[i];
      final x = center.dx - band / 2 + step * i + (step - barWidth) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, base - height, barWidth, height),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FacePainter oldDelegate) =>
      oldDelegate.face != face || oldDelegate.palette != palette;
}
