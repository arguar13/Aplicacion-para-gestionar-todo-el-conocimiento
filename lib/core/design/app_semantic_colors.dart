import 'package:cristo_es_el_salvador/core/design/app_colors.dart';
import 'package:flutter/material.dart';

/// `ColorScheme` de Material 3 no tiene un slot para "éxito" ni
/// "advertencia" (solo `error`) — para exponerlos igual vía
/// `Theme.of(context)` (y no como constantes sueltas importadas a mano en
/// cada widget) se usa una `ThemeExtension`, el mecanismo oficial de
/// Flutter para agregar colores propios al tema.
///
/// Uso: `Theme.of(context).extension<AppSemanticColors>()!.success`.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
  });

  static const light = AppSemanticColors(
    success: AppColors.successLight,
    onSuccess: AppColors.onSuccessLight,
    warning: AppColors.warningLight,
    onWarning: AppColors.onWarningLight,
  );

  static const dark = AppSemanticColors(
    success: AppColors.successDark,
    onSuccess: AppColors.onSuccessDark,
    warning: AppColors.warningDark,
    onWarning: AppColors.onWarningDark,
  );

  final Color success;
  final Color onSuccess;
  final Color warning;
  final Color onWarning;

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? warning,
    Color? onWarning,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
    );
  }
}
