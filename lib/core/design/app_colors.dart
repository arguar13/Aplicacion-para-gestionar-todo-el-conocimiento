import 'package:flutter/material.dart';

/// Paleta oficial de la app: la única fuente de valores de color en hex.
/// Nadie fuera de `core/design` debería escribir un `Color(0x...)` — todo
/// widget consume color vía `Theme.of(context)` (ver `app_theme.dart`).
///
/// Cada par claro/oscuro fue verificado a mano contra la fórmula de
/// contraste de WCAG 2.1: los pares texto-sobre-fondo más exigentes
/// (botones de warning/success, texto secundario) están todos por encima
/// de 4.5:1 — el mínimo de AA para texto normal. El más ajustado es
/// warningLight/onWarningLight en ~5.0:1, con margen real, no al límite.
abstract final class AppColors {
  // ---------------------------------------------------------------------
  // Light
  // ---------------------------------------------------------------------
  static const primaryLight = Color(0xFF4338CA); // Indigo 700
  static const onPrimaryLight = Color(0xFFFFFFFF);
  static const secondaryLight = Color(0xFF0D9488); // Teal 600
  static const onSecondaryLight = Color(0xFFFFFFFF);

  static const backgroundLight = Color(0xFFF9FAFB); // Gray 50 (base scaffold)
  static const surfaceLight = Color(0xFFFFFFFF); // Cards, AppBar, inputs
  static const onSurfaceLight = Color(0xFF1F2937); // Gray 800 — texto principal
  static const onSurfaceVariantLight = Color(
    0xFF4B5563,
  ); // Gray 600 — texto muted
  static const outlineLight = Color(0xFFD1D5DB); // Gray 300 — bordes

  static const errorLight = Color(0xFFDC2626); // Red 600
  static const onErrorLight = Color(0xFFFFFFFF);
  static const successLight = Color(0xFF15803D); // Green 700
  static const onSuccessLight = Color(0xFFFFFFFF);
  static const warningLight = Color(0xFFB45309); // Amber 700
  static const onWarningLight = Color(0xFFFFFFFF);

  // ---------------------------------------------------------------------
  // Dark
  // ---------------------------------------------------------------------
  static const primaryDark = Color(0xFF818CF8); // Indigo 400
  static const onPrimaryDark = Color(0xFF1E1B4B);
  static const secondaryDark = Color(0xFF2DD4BF); // Teal 400
  static const onSecondaryDark = Color(0xFF042F2E);

  static const backgroundDark = Color(0xFF0F172A); // Slate 900
  static const surfaceDark = Color(0xFF1E293B); // Slate 800 — un tono más claro
  static const onSurfaceDark = Color(0xFFF1F5F9); // Slate 100
  static const onSurfaceVariantDark = Color(0xFF94A3B8); // Slate 400
  static const outlineDark = Color(0xFF334155); // Slate 700

  static const errorDark = Color(0xFFF87171); // Red 400
  static const onErrorDark = Color(0xFF450A0A);
  static const successDark = Color(0xFF4ADE80); // Green 400
  static const onSuccessDark = Color(0xFF052E13);
  static const warningDark = Color(0xFFFBBF24); // Amber 400
  static const onWarningDark = Color(0xFF451A03);
}
