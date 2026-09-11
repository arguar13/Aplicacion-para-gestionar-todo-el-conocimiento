import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Escala tipográfica de la app: Inter, elegida por ser una fuente
/// diseñada específicamente para UI (buena legibilidad en textos chicos,
/// números tabulares, funciona igual de bien en pantallas grandes de Web
/// que en móvil).
///
/// No fija tamaños distintos "para Web" vs "para móvil" a propósito: el
/// escalado real entre dispositivos lo resuelve Flutter solo, a través del
/// `TextScaler` de `MediaQuery` (que respeta la config de accesibilidad
/// del sistema operativo). Hardcodear tamaños distintos por breakpoint
/// pelearía contra eso — el ancho de pantalla lo maneja el layout
/// (`Wrap`/`ConstrainedBox`/etc.), no el tamaño de fuente.
///
/// Sin color: `AppTheme` aplica el color correcto (claro/oscuro) encima
/// con `.apply(bodyColor: ..., displayColor: ...)`. Los widgets nunca
/// importan esta clase directamente — siempre `Theme.of(context).textTheme`.
abstract final class AppTypography {
  static TextTheme get textTheme => GoogleFonts.interTextTheme();
}
