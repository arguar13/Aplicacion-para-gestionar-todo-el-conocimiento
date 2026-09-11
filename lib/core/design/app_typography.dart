import 'package:flutter/material.dart';

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
/// La tipografía se empaqueta con la app (ver pubspec.yaml y
/// tool/fetch_inter_font.sh) en vez de bajarse en tiempo de ejecución como
/// hacía `google_fonts`: en la web, sin conexión a la CDN de Google, esa
/// carga nunca se resolvía y el texto entero quedaba invisible —el
/// principio 1 ya la prohibía por bajar algo sin permiso explícito, pero
/// además rompía la app de verdad—. Ver la decisión 12 en
/// docs/arquitectura.md. `ThemeData.light().textTheme` es la misma base
/// que usaba `GoogleFonts.interTextTheme()`: dos pesos nada más, regular y
/// medio, que son los dos que emplea la escala de Material 3 por defecto.
///
/// Sin color: `AppTheme` aplica el color correcto (claro/oscuro) encima
/// con `.apply(bodyColor: ..., displayColor: ...)`. Los widgets nunca
/// importan esta clase directamente — siempre `Theme.of(context).textTheme`.
abstract final class AppTypography {
  static TextTheme get textTheme =>
      ThemeData.light().textTheme.apply(fontFamily: 'Inter');
}
