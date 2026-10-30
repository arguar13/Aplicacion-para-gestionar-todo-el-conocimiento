import 'dart:convert';

import 'package:flutter/foundation.dart';

/// La cara de una voz (F47, paso 3, decisión D): un retrato propio y
/// abstracto —su color, sus iniciales y su onda—, nunca la foto de una
/// persona. Una foto diría que esa voz es de esa persona, y no lo es.
///
/// **La misma voz da siempre la misma cara**, en cada apertura, en cada
/// teléfono y en cada versión de la app: sale de una huella del
/// identificador de la voz (FNV-1a de 32 bits sobre su UTF-8), no de
/// `String.hashCode`, que Dart no promete igual entre ejecuciones. El tema
/// cambia la luz de los colores, no el tono: en claro y en oscuro se reconoce
/// la misma cara.
@immutable
class VoiceFace {
  const VoiceFace._({
    required this.hue,
    required this.accentHue,
    required this.initials,
    required this.wave,
    required this.tilt,
  });

  /// La cara de la voz [id], con las iniciales de [label] —su nombre, o su
  /// número si no tiene—.
  factory VoiceFace.of(String id, String label) {
    var hash = _fnv1a(id);
    int take(int bits) {
      final value = hash & ((1 << bits) - 1);
      hash = _mix(hash);
      return value;
    }

    final hue = take(9) % 360;
    // El segundo tono, a una distancia que se note y no choque: de 40° a 159°.
    final accentHue = (hue + 40 + take(7) % 120) % 360;
    final wave = List<double>.unmodifiable([
      for (var bar = 0; bar < waveBars; bar++) 0.25 + (take(6) / 63) * 0.75,
    ]);
    final tilt = take(4) / 15;
    return VoiceFace._(
      hue: hue.toDouble(),
      accentHue: accentHue.toDouble(),
      initials: initialsOf(label),
      wave: wave,
      tilt: tilt,
    );
  }

  /// Cuántas barras tiene la onda.
  static const waveBars = 7;

  /// El tono del fondo, de 0 a 360.
  final double hue;

  /// El tono del degradé y de la onda.
  final double accentHue;

  /// Hasta dos letras: «Daniela» → «D»; «Sharvard F» → «SF»; «12» → «12».
  final String initials;

  /// El alto de cada barra de la onda, de 0,25 a 1.
  final List<double> wave;

  /// Hacia dónde va el degradé, de 0 a 1 (una vuelta).
  final double tilt;

  @override
  bool operator ==(Object other) =>
      other is VoiceFace &&
      other.hue == hue &&
      other.accentHue == accentHue &&
      other.initials == initials &&
      other.tilt == tilt &&
      listEquals(other.wave, wave);

  @override
  int get hashCode =>
      Object.hash(hue, accentHue, initials, tilt, Object.hashAll(wave));
}

/// Las iniciales de un nombre: la primera letra de cada una de sus dos
/// primeras palabras, en mayúscula; un número, tal cual.
@visibleForTesting
String initialsOf(String label) {
  final words = label.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.isEmpty) return '?';
  if (int.tryParse(words.first) != null) return words.first;
  return words
      .take(2)
      .map((word) => String.fromCharCode(word.runes.first).toUpperCase())
      .join();
}

const _fnvOffset = 0x811C9DC5;

/// El primo de FNV de 32 bits es 2²⁴ + 0x193: se multiplica en dos partes
/// para que el producto no pase de 2⁵³ —en la web los enteros son `double`, y
/// `h * 0x01000193` entero perdería los bits de abajo—, y la cara sea la
/// misma en el teléfono, en Windows y en la web.
int _fnv1a(String text) {
  var hash = _fnvOffset;
  for (final byte in utf8.encode(text)) {
    final h = (hash ^ byte) & 0xFFFFFFFF;
    hash = (((h << 24) & 0xFFFFFFFF) + h * 0x193) & 0xFFFFFFFF;
  }
  return hash;
}

/// Revuelve la huella para sacar el próximo número (xorshift de 32 bits):
/// cada rasgo de la cara sale de bits distintos.
int _mix(int value) {
  var x = value == 0 ? _fnvOffset : value;
  x ^= (x << 13) & 0xFFFFFFFF;
  x ^= x >> 17;
  x ^= (x << 5) & 0xFFFFFFFF;
  return x & 0xFFFFFFFF;
}
