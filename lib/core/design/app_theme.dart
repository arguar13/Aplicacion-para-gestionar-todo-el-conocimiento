import 'package:cristo_es_el_salvador/core/design/app_colors.dart';
import 'package:cristo_es_el_salvador/core/design/app_semantic_colors.dart';
import 'package:cristo_es_el_salvador/core/design/app_typography.dart';
import 'package:flutter/material.dart';

/// Único punto de construcción de los `ThemeData` de la app. Todo widget
/// debe leer estilos vía `Theme.of(context)` — nunca `AppColors`/
/// `AppTypography` directamente ni valores hardcodeados.
abstract final class AppTheme {
  static const _borderRadius = 12.0;

  static ThemeData get lightTheme => _build(
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primaryLight)
        .copyWith(
          primary: AppColors.primaryLight,
          onPrimary: AppColors.onPrimaryLight,
          secondary: AppColors.secondaryLight,
          onSecondary: AppColors.onSecondaryLight,
          surface: AppColors.surfaceLight,
          onSurface: AppColors.onSurfaceLight,
          onSurfaceVariant: AppColors.onSurfaceVariantLight,
          outline: AppColors.outlineLight,
          error: AppColors.errorLight,
          onError: AppColors.onErrorLight,
        ),
    semanticColors: AppSemanticColors.light,
    scaffoldBackgroundColor: AppColors.backgroundLight,
  );

  static ThemeData get darkTheme => _build(
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: AppColors.primaryDark,
          brightness: Brightness.dark,
        ).copyWith(
          primary: AppColors.primaryDark,
          onPrimary: AppColors.onPrimaryDark,
          secondary: AppColors.secondaryDark,
          onSecondary: AppColors.onSecondaryDark,
          surface: AppColors.surfaceDark,
          onSurface: AppColors.onSurfaceDark,
          onSurfaceVariant: AppColors.onSurfaceVariantDark,
          outline: AppColors.outlineDark,
          error: AppColors.errorDark,
          onError: AppColors.onErrorDark,
        ),
    semanticColors: AppSemanticColors.dark,
    scaffoldBackgroundColor: AppColors.backgroundDark,
  );

  /// `ColorScheme.fromSeed` genera automáticamente los ~20 roles de
  /// Material 3 (surfaceContainer, outlineVariant, inverseSurface, etc.)
  /// con una paleta tonal coherente y accesible; encima se pisan con
  /// `.copyWith` los roles donde la marca necesita un valor exacto
  /// (primary/secondary/surface/error) en vez de dejar que el algoritmo
  /// de Material los derive del seed. Evita tener que definir a mano
  /// cada uno de esos ~20 colores.
  static ThemeData _build({
    required ColorScheme colorScheme,
    required AppSemanticColors semanticColors,
    required Color scaffoldBackgroundColor,
  }) {
    final textTheme = AppTypography.textTheme.apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackgroundColor,
      textTheme: textTheme,
      extensions: [semanticColors],

      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          disabledBackgroundColor: colorScheme.onSurface.withValues(
            alpha: 0.12,
          ),
          disabledForegroundColor: colorScheme.onSurface.withValues(
            alpha: 0.38,
          ),
          elevation: 1,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_borderRadius),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),

      // El botón real de la app (`PrimaryButton`) usa `FilledButton`, no
      // `ElevatedButton` — se tematizan ambos para que ninguno de los dos
      // dependa de estilos por defecto de Material.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_borderRadius),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        errorStyle: textTheme.bodySmall?.copyWith(color: colorScheme.error),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_borderRadius),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_borderRadius),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_borderRadius),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_borderRadius),
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_borderRadius),
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_borderRadius),
          borderSide: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.5),
          ),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_borderRadius),
        ),
      ),
    );
  }
}
