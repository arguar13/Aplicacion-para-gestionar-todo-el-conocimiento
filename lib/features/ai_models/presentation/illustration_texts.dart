import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/daily_quota.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_price_table.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/ai_models/presentation/ai_model_texts.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cómo se le dice a la persona cada cosa de las ilustraciones con IA (F43):
/// un solo lugar para que el aviso, la tabla y Ajustes digan lo mismo con
/// las mismas palabras.
extension IllustrationProviderTexts on IllustrationProvider {
  String label(AppLocalizations l10n) => switch (this) {
    IllustrationProvider.gemini => l10n.lmProviderGemini,
    IllustrationProvider.openAi => l10n.lmProviderOpenAi,
    IllustrationProvider.huggingFace => l10n.f43AiProviderHuggingFace,
    IllustrationProvider.onDevice => l10n.f43AiProviderOnDevice,
  };

  IconData get icon => switch (this) {
    IllustrationProvider.gemini => AiProvider.gemini.icon,
    IllustrationProvider.openAi => AiProvider.openAi.icon,
    IllustrationProvider.huggingFace => Icons.diversity_2_outlined,
    IllustrationProvider.onDevice => Icons.memory_outlined,
  };
}

/// Por qué no se puede dibujar, en minúscula, con el nombre de la cuenta
/// ([account]) cuando el motivo es de ella. Con `ImageFailure.noAccount` y
/// [textProvider] que no dibuja, «Claude no genera imágenes».
String illustrationReason(
  AppLocalizations l10n,
  ImageFailure failure, {
  String? account,
  AiProvider? textProvider,
}) {
  final name = account ?? '';
  return switch (failure) {
    ImageFailure.noBilling => l10n.f43AiReasonNoBilling(name),
    ImageFailure.orgUnverified => l10n.f43AiReasonOrgUnverified(name),
    ImageFailure.noCredits => l10n.f43AiReasonNoCredits(name),
    ImageFailure.quotaExhausted => l10n.f43AiReasonQuotaExhausted(name),
    ImageFailure.rateLimited => l10n.f43AiReasonRateLimited,
    ImageFailure.contentRefused => l10n.f43AiReasonContentRefused,
    ImageFailure.invalidKey => l10n.f43AiReasonInvalidKey(name),
    ImageFailure.forbidden => l10n.f43AiReasonForbidden(name),
    ImageFailure.modelNotFound => l10n.f43AiReasonModelNotFound,
    ImageFailure.noImageModel => l10n.f43AiReasonNoImageModel(name),
    ImageFailure.noImage => l10n.f43AiReasonNoImage,
    ImageFailure.modelNotDownloaded => l10n.f43AiReasonModelNotDownloaded,
    ImageFailure.deviceTooSmall => l10n.f43AiReasonDeviceTooSmall,
    ImageFailure.notEnoughMemory => l10n.f43DeviceReasonNotEnoughMemory,
    ImageFailure.unsupportedDevice => l10n.f43DeviceReasonUnsupported,
    ImageFailure.cancelled => l10n.f43DeviceReasonCancelled,
    ImageFailure.network => l10n.f43AiReasonNetwork,
    ImageFailure.timeout => l10n.f43AiReasonTimeout,
    ImageFailure.unavailable => l10n.f43AiReasonUnavailable,
    ImageFailure.badRequest => l10n.f43AiReasonBadRequest,
    ImageFailure.noAccount =>
      textProvider == AiProvider.anthropic || textProvider == AiProvider.gemma
          ? l10n.f43AiReasonProviderCannot(textProvider!.label(l10n))
          : l10n.f43AiReasonNoAccount,
    ImageFailure.unknown => l10n.f43AiReasonUnknown,
  };
}

/// La licencia de un modelo abierto, en una línea.
String openModelLicenseLine(AppLocalizations l10n, OpenModelLicense license) =>
    switch (license) {
      OpenModelLicense.apache2 => l10n.f43AiLicenseApache,
      OpenModelLicense.stabilityCommunity => l10n.f43AiLicenseStability,
      OpenModelLicense.openRailPlusPlus => l10n.f43DeviceLicenseOpenRail,
    };

/// Por qué no puede escribir la IA elegida, en minúscula.
String textProblemReason(AppLocalizations l10n, LanguageModelStatus status) =>
    switch (status) {
      LanguageModelReady() => '',
      LanguageModelNeedsDownload() => l10n.f43AiTextNeedsDownload,
      LanguageModelNeedsAccount(:final provider) => l10n.f43AiTextNeedsAccount(
        provider.label(l10n),
      ),
      LanguageModelOutOfQuota(keysRejected: true) => l10n.f43AiTextKeysRejected,
      LanguageModelOutOfQuota() => l10n.f43AiTextOutOfQuota,
      LanguageModelBackgroundCapReached() => l10n.f43AiTextOutOfQuota,
    };

String _locale(BuildContext context) =>
    Localizations.localeOf(context).toLanguageTag();

/// Un monto en dólares, corto y con los decimales que hacen falta: «US$
/// 0,0084», «US$ 0,034», «US$ 1,20».
String aiUsd(BuildContext context, double usd) {
  final pattern = usd == 0
      ? '0'
      : usd < 0.01
      ? '0.0###'
      : usd < 1
      ? '0.0##'
      : '#,##0.00';
  return 'US\$ ${NumberFormat(pattern, _locale(context)).format(usd)}';
}

/// Un porcentaje redondo: «18 %», «< 1 %» si es poco pero no nada.
String aiPercent(BuildContext context, double percent) {
  if (percent > 0 && percent < 1) {
    return '< ${NumberFormat.percentPattern(_locale(context)).format(0.01)}';
  }
  return NumberFormat.percentPattern(
    _locale(context),
  ).format(percent.round() / 100);
}

/// Una duración para leer: «45 segundos», «3 minutos», «1 h 20 min».
String aiDuration(AppLocalizations l10n, Duration duration) {
  if (duration.inSeconds < 60) {
    return l10n.f43AiSeconds(duration.inSeconds.clamp(1, 59));
  }
  final minutes = (duration.inSeconds / 60).round();
  if (minutes < 60) return l10n.f43AiMinutes(minutes);
  return l10n.f43AiHours(minutes ~/ 60, minutes % 60);
}

/// El tamaño de una ilustración, como se muestra.
String illustrationSizeLabel(AppLocalizations l10n, IllustrationSize size) =>
    switch (size) {
      IllustrationSize.small => l10n.f43AiSizeSmall,
      IllustrationSize.standard => l10n.f43AiSizeStandard,
      IllustrationSize.large => l10n.f43AiSizeLarge,
    };

/// Las partes de una cuota, juntas: «250 pedidos · 20 imágenes · US$ 1,00».
/// Vacía si no topea nada.
String dailyQuotaParts(BuildContext context, DailyQuota quota) {
  final l10n = AppLocalizations.of(context)!;
  return [
    if (quota.requests case final n?) l10n.f43AiQuotaRequests(n),
    if (quota.tokens case final n?) l10n.f43AiQuotaTokens(aiTokens(context, n)),
    if (quota.images case final n?) l10n.f43AiQuotaImages(n),
    if (quota.usd case final usd?) aiUsd(context, usd),
  ].join(' · ');
}
