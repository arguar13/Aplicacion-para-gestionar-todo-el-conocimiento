import 'package:flutter/material.dart';
import 'package:sinapsis/core/design/app_colors.dart';
import 'package:sinapsis/core/design/app_semantic_colors.dart';

/// Los colores de un tema con nombre (F39, decisión E): Sepia, Noche, Bosque,
/// Océano, Lavanda y Grafito. Como `AppColors`, es de los pocos lugares donde
/// se escribe un color en hex; el resto de la app los lee del `Theme`.
///
/// Cada tema trae lo que lo define —fondo, superficie, texto, acento— y el
/// resto del `ColorScheme` se deriva de eso en [colorScheme]: las
/// superficies de las tarjetas son la superficie con un poco de texto
/// mezclado, y los contenedores del acento, la superficie con un poco de
/// acento. Así cada tema son once colores y no treinta, y los pares de
/// texto-sobre-fondo no se pueden desparejar entre sí.
///
/// Todos los pares de texto cumplen AA (4.5:1) —lo comprueba
/// `app_theme_choice_test.dart`—, incluido el texto sobre [highlight], el
/// color con el que se pintan los subrayados de siempre.
enum AppThemePalette {
  /// Papel cálido para leer largo.
  sepia(
    brightness: Brightness.light,
    background: Color(0xFFF4ECD8),
    surface: Color(0xFFFBF5E6),
    onSurface: Color(0xFF3B2F22),
    onSurfaceVariant: Color(0xFF6B5A47),
    outline: Color(0xFFD8CBB0),
    primary: Color(0xFF8A4B1F),
    onPrimary: Color(0xFFFFFFFF),
    secondary: Color(0xFF566F43),
    onSecondary: Color(0xFFFFFFFF),
    highlight: Color(0xFFF0DC9A),
  ),

  /// Negro puro de fondo: en una pantalla OLED, el píxel apagado no gasta.
  night(
    brightness: Brightness.dark,
    background: Color(0xFF000000),
    surface: Color(0xFF0B0B0D),
    onSurface: Color(0xFFE8E8EA),
    onSurfaceVariant: Color(0xFFA0A0A8),
    outline: Color(0xFF2E2E33),
    primary: Color(0xFF9FB4FF),
    onPrimary: Color(0xFF0B1233),
    secondary: Color(0xFF7FD6C8),
    onSecondary: Color(0xFF04201C),
    highlight: Color(0xFF4A4220),
  ),

  forest(
    brightness: Brightness.dark,
    background: Color(0xFF0F1A14),
    surface: Color(0xFF16251C),
    onSurface: Color(0xFFE3EDE6),
    onSurfaceVariant: Color(0xFFA3B8AA),
    outline: Color(0xFF2D4036),
    primary: Color(0xFF8FCB9B),
    onPrimary: Color(0xFF0B2412),
    secondary: Color(0xFFD2B87A),
    onSecondary: Color(0xFF2B2108),
    highlight: Color(0xFF4A4A24),
  ),

  ocean(
    brightness: Brightness.dark,
    background: Color(0xFF0B1C26),
    surface: Color(0xFF112A38),
    onSurface: Color(0xFFE2EEF4),
    onSurfaceVariant: Color(0xFF9DB8C7),
    outline: Color(0xFF24465A),
    primary: Color(0xFF6CC4E8),
    onPrimary: Color(0xFF04222F),
    secondary: Color(0xFF7FE0C9),
    onSecondary: Color(0xFF03231C),
    highlight: Color(0xFF4B4A2A),
  ),

  lavender(
    brightness: Brightness.light,
    background: Color(0xFFF5F1FA),
    surface: Color(0xFFFCFAFF),
    onSurface: Color(0xFF2A2238),
    onSurfaceVariant: Color(0xFF62587A),
    outline: Color(0xFFD6CCE6),
    primary: Color(0xFF6B4FB0),
    onPrimary: Color(0xFFFFFFFF),
    secondary: Color(0xFF9A4F86),
    onSecondary: Color(0xFFFFFFFF),
    highlight: Color(0xFFF6E3A1),
  ),

  graphite(
    brightness: Brightness.dark,
    background: Color(0xFF1B1D20),
    surface: Color(0xFF25282C),
    onSurface: Color(0xFFE6E8EB),
    onSurfaceVariant: Color(0xFFA6ABB2),
    outline: Color(0xFF3A3E44),
    primary: Color(0xFFB8C4D6),
    onPrimary: Color(0xFF1A2433),
    secondary: Color(0xFFD9A66B),
    onSecondary: Color(0xFF2D1C06),
    highlight: Color(0xFF51482C),
  );

  const AppThemePalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.onSecondary,
    required this.highlight,
  });

  final Brightness brightness;

  /// El fondo de las pantallas.
  final Color background;

  /// Las barras, las tarjetas y los campos: un paso por encima del fondo.
  final Color surface;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outline;
  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color onSecondary;

  /// El fondo de los subrayados sin color elegido (`tertiaryContainer`), con
  /// [onSurface] encima.
  final Color highlight;

  bool get _dark => brightness == Brightness.dark;

  /// La superficie con [amount] de [onSurface] mezclado: el escalón de una
  /// tarjeta sobre la superficie. El texto oscurece un tema claro y aclara
  /// uno oscuro, así que el escalón siempre se separa de la superficie.
  Color _step(double amount) => Color.lerp(surface, onSurface, amount)!;

  /// La superficie con un poco de [accent]: el contenedor de un acento.
  Color _container(Color accent) =>
      Color.lerp(surface, accent, _dark ? 0.30 : 0.22)!;

  /// El `ColorScheme` del tema. `fromSeed` rellena los roles que acá no se
  /// fijan (los fijos, los de terciario) con una paleta tonal coherente; todo
  /// lo que se ve en pantalla sale de los colores de la paleta.
  ColorScheme get colorScheme {
    final error = _dark ? AppColors.errorDark : AppColors.errorLight;
    final onError = _dark ? AppColors.onErrorDark : AppColors.onErrorLight;
    return ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: _container(primary),
      onPrimaryContainer: onSurface,
      secondary: secondary,
      onSecondary: onSecondary,
      secondaryContainer: _container(secondary),
      onSecondaryContainer: onSurface,
      tertiaryContainer: highlight,
      onTertiaryContainer: onSurface,
      error: error,
      onError: onError,
      surface: surface,
      onSurface: onSurface,
      onSurfaceVariant: onSurfaceVariant,
      surfaceDim: _step(0.08),
      surfaceBright: surface,
      surfaceContainerLowest: surface,
      surfaceContainerLow: _step(0.03),
      surfaceContainer: _step(0.05),
      surfaceContainerHigh: _step(0.08),
      surfaceContainerHighest: _step(0.11),
      outline: outline,
      outlineVariant: _step(0.16),
      inverseSurface: onSurface,
      onInverseSurface: surface,
      inversePrimary: primary,
    );
  }

  AppSemanticColors get semanticColors =>
      _dark ? AppSemanticColors.dark : AppSemanticColors.light;
}
