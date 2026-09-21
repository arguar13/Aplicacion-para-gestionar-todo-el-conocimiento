import 'package:flutter/foundation.dart';

/// Cómo terminó una compactación que no falló.
@immutable
class CompactionResult {
  const CompactionResult({
    required this.bytesBefore,
    required this.bytesAfter,
    required this.elapsed,
    this.wasCancelled = false,
    this.sourcesVerified = 0,
  });

  /// Lo que ocupaba el archivo de la bóveda antes.
  final int bytesBefore;

  /// Lo que ocupa ahora.
  final int bytesAfter;

  /// Cuánto tardó, de punta a punta —contando la comprobación—.
  final Duration elapsed;

  /// Si se pidió parar y se paró entre dos tramos. Lo devuelto hasta ahí quedó
  /// devuelto: la bóveda está completa y más chica; solo falta el resto.
  final bool wasCancelled;

  /// Cuántas fuentes con texto se comprobaron después: sus chunks reconstruyen
  /// su texto. Cero si no se comprobó ninguna, porque no había nada que
  /// comprobar o porque la compactación se canceló antes.
  final int sourcesVerified;

  /// Lo que se devolvió al sistema. Nunca es negativo: compactar no agranda.
  int get freedBytes => bytesBefore > bytesAfter ? bytesBefore - bytesAfter : 0;

  @override
  String toString() =>
      'CompactionResult($bytesBefore → $bytesAfter bytes, '
      '${wasCancelled ? 'cancelada, ' : ''}'
      '$sourcesVerified fuentes comprobadas, $elapsed)';
}
