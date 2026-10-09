import 'package:flutter/material.dart';

/// Los colores de las estadísticas de repaso (F31, ola 2, decisión 72).
///
/// Dos conjuntos categóricos, cada uno elegido por modo (claro y oscuro son
/// pasos distintos de los mismos tonos, no un volteo automático) y comprobado
/// con el validador de paletas del skill de visualización —diferencia entre
/// vecinos para daltonismo y visión normal, banda de luminosidad y croma—:
///
/// - **Etapas** (azul, naranja, aguamarina, violeta): nuevas, aprendiendo,
///   jóvenes, maduras. Las pausadas van en gris, que no es un tono sino un
///   «apagado», como corresponde a lo que no participa.
/// - **Botones** (rojo, amarillo, aguamarina, azul): De nuevo, Difícil, Bien,
///   Fácil. En el claro, el amarillo y el aguamarina quedan por debajo de 3:1
///   contra el fondo: por eso cada segmento lleva su rótulo y su número al
///   lado, y la lista de números es la vista de tabla. El color nunca es lo
///   único que dice qué es cada tramo.
class CardStatsPalette {
  const CardStatsPalette._({
    required this.newCards,
    required this.learning,
    required this.young,
    required this.mature,
    required this.suspended,
    required this.again,
    required this.hard,
    required this.good,
    required this.easy,
  });

  /// Los de [context], según el modo claro u oscuro del tema.
  factory CardStatsPalette.of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  static const light = CardStatsPalette._(
    newCards: Color(0xFF2A78D6),
    learning: Color(0xFFEB6834),
    young: Color(0xFF1BAF7A),
    mature: Color(0xFF4A3AA7),
    suspended: Color(0xFF8A8A85),
    again: Color(0xFFE34948),
    hard: Color(0xFFEDA100),
    good: Color(0xFF1BAF7A),
    easy: Color(0xFF2A78D6),
  );

  static const dark = CardStatsPalette._(
    newCards: Color(0xFF3987E5),
    learning: Color(0xFFD95926),
    young: Color(0xFF199E70),
    mature: Color(0xFF9085E9),
    suspended: Color(0xFF8A8A85),
    again: Color(0xFFD73B52),
    hard: Color(0xFFC98500),
    good: Color(0xFF199E70),
    easy: Color(0xFF3987E5),
  );

  final Color newCards;
  final Color learning;
  final Color young;
  final Color mature;
  final Color suspended;

  final Color again;
  final Color hard;
  final Color good;
  final Color easy;
}
