import 'package:flutter/material.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/design/app_theme_palette.dart';

/// Los temas entre los que se elige en Ajustes (F39, decisión E): el del
/// sistema, el claro y el oscuro de siempre, y seis con nombre.
///
/// Cada uno sabe darle a `MaterialApp` lo que necesita —[theme], [darkTheme]
/// y [mode]— y cuál es su brillo, para que todo lo que decide un color por
/// `Theme.of(context).brightness` (los resaltadores de estudiar, los
/// subrayados, las estadísticas de las tarjetas) acierte también en un tema
/// con nombre: Sepia y Lavanda son claros; Noche, Bosque, Océano y Grafito,
/// oscuros.
///
/// [name] es lo que se guarda. Los tres primeros se llaman igual que el
/// `ThemeMode` que se guardaba antes (`system`, `light`, `dark`), así que lo
/// que ya estaba guardado se lee tal cual: ver [fromStorage].
enum AppThemeChoice {
  system,
  light,
  dark,

  /// Papel cálido para leer largo.
  sepia,

  /// Negro puro, que en una pantalla OLED gasta menos.
  night,
  forest,
  ocean,
  lavender,
  graphite;

  /// Lo guardado en [name], o el del sistema si no hay nada o no se conoce
  /// (un tema que una versión futura sacó, un valor roto).
  static AppThemeChoice fromStorage(String? name) => values.firstWhere(
    (choice) => choice.name == name,
    orElse: () => AppThemeChoice.system,
  );

  /// Los colores del tema, si es uno con nombre; `null` en el del sistema, el
  /// claro y el oscuro, que son los de siempre.
  AppThemePalette? get palette => switch (this) {
    AppThemeChoice.system ||
    AppThemeChoice.light ||
    AppThemeChoice.dark => null,
    AppThemeChoice.sepia => AppThemePalette.sepia,
    AppThemeChoice.night => AppThemePalette.night,
    AppThemeChoice.forest => AppThemePalette.forest,
    AppThemeChoice.ocean => AppThemePalette.ocean,
    AppThemeChoice.lavender => AppThemePalette.lavender,
    AppThemeChoice.graphite => AppThemePalette.graphite,
  };

  /// El brillo del tema, o `null` si lo decide el sistema.
  Brightness? get brightness => switch (this) {
    AppThemeChoice.system => null,
    AppThemeChoice.light => Brightness.light,
    AppThemeChoice.dark => Brightness.dark,
    _ => palette!.brightness,
  };

  /// El `themeMode` de `MaterialApp`.
  ThemeMode get mode => switch (brightness) {
    null => ThemeMode.system,
    Brightness.light => ThemeMode.light,
    Brightness.dark => ThemeMode.dark,
  };

  /// El `theme` de `MaterialApp`: el claro, o el del tema con nombre.
  ThemeData get theme => palette == null ? _lightOf : _own;

  /// El `darkTheme` de `MaterialApp`: el oscuro, o el del tema con nombre.
  /// Un tema con nombre fija las dos ranuras al mismo: [mode] ya dice cuál
  /// se usa, y el del sistema no lo cambia.
  ThemeData get darkTheme => palette == null ? _darkOf : _own;

  /// Lo que se ve en la muestra de Ajustes: el tema mismo, o —en el del
  /// sistema— el claro y el oscuro lado a lado.
  List<ThemeData> get previews => switch (this) {
    AppThemeChoice.system => [_lightOf, _darkOf],
    AppThemeChoice.light => [_lightOf],
    AppThemeChoice.dark => [_darkOf],
    _ => [_own],
  };

  /// Armar un `ThemeData` es caro y `MaterialApp` los pide en cada
  /// reconstrucción: se arma una vez cada uno.
  static final _built = <Object, ThemeData>{};

  static ThemeData get _lightOf =>
      _built.putIfAbsent('light', () => AppTheme.lightTheme);

  static ThemeData get _darkOf =>
      _built.putIfAbsent('dark', () => AppTheme.darkTheme);

  ThemeData get _own =>
      _built.putIfAbsent(this, () => AppTheme.fromPalette(palette!));
}
