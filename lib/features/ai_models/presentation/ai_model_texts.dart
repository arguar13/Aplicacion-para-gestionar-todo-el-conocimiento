import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cómo se le dice a la persona cada cosa de la IA (F32): un solo lugar para
/// que la pantalla del modelo, los avisos y los mensajes de «qué falta» digan
/// lo mismo con las mismas palabras.
extension AiProviderTexts on AiProvider {
  String label(AppLocalizations l10n) => switch (this) {
    AiProvider.gemini => l10n.lmProviderGemini,
    AiProvider.gemma => l10n.lmProviderGemma,
    AiProvider.openAi => l10n.lmProviderOpenAi,
    AiProvider.anthropic => l10n.lmProviderAnthropic,
  };

  String detail(AppLocalizations l10n) => switch (this) {
    AiProvider.gemini => l10n.lmProviderGeminiDetail,
    AiProvider.gemma => l10n.lmProviderGemmaDetail,
    AiProvider.openAi => l10n.lmProviderOpenAiDetail,
    AiProvider.anthropic => l10n.lmProviderAnthropicDetail,
  };

  IconData get icon => switch (this) {
    AiProvider.gemini => Icons.auto_awesome,
    AiProvider.gemma => Icons.phone_android,
    AiProvider.openAi => Icons.blur_on,
    AiProvider.anthropic => Icons.brightness_7_outlined,
  };
}

/// Por qué falló algo, en minúscula: va después de «No anduvo:» o del nombre
/// de la cuenta.
String aiFailureReason(AppLocalizations l10n, CloudModelFailure failure) =>
    switch (failure) {
      CloudModelFailure.invalidKey => l10n.lmFailureInvalidKey,
      CloudModelFailure.forbidden => l10n.lmFailureForbidden,
      CloudModelFailure.rateLimited => l10n.lmFailureRateLimited,
      CloudModelFailure.quotaExhausted => l10n.lmFailureQuotaExhausted,
      CloudModelFailure.modelNotFound => l10n.lmFailureModelNotFound,
      CloudModelFailure.unavailable => l10n.lmFailureUnavailable,
      CloudModelFailure.blocked => l10n.lmFailureBlocked,
      CloudModelFailure.network => l10n.lmFailureNetwork,
      CloudModelFailure.timeout => l10n.lmFailureTimeout,
      CloudModelFailure.cutOff => l10n.lmFailureCutOff,
      CloudModelFailure.badRequest => l10n.lmFailureBadRequest,
      CloudModelFailure.tooLong => l10n.lmFailureTooLong,
      CloudModelFailure.noAccount => l10n.lmFailureNoAccount,
      CloudModelFailure.backgroundCap => l10n.lmFailureBackgroundCap,
      CloudModelFailure.unknown => l10n.lmFailureUnknown,
    };

/// Qué pasó de verdad y qué hacer, en una o dos frases completas (F39): para
/// el error final de lo que la persona pidió, donde un motivo suelto no
/// alcanza.
String aiFailureHelp(AppLocalizations l10n, CloudModelFailure failure) =>
    switch (failure) {
      CloudModelFailure.invalidKey => l10n.lmHelpInvalidKey,
      CloudModelFailure.forbidden => l10n.lmHelpForbidden,
      CloudModelFailure.rateLimited => l10n.lmHelpRateLimited,
      CloudModelFailure.quotaExhausted => l10n.lmHelpQuotaExhausted,
      CloudModelFailure.modelNotFound => l10n.lmHelpModelNotFound,
      CloudModelFailure.unavailable => l10n.lmHelpUnavailable,
      CloudModelFailure.blocked => l10n.lmHelpBlocked,
      CloudModelFailure.network => l10n.lmHelpNetwork,
      CloudModelFailure.timeout => l10n.lmHelpTimeout,
      CloudModelFailure.cutOff => l10n.lmHelpCutOff,
      CloudModelFailure.badRequest => l10n.lmHelpBadRequest,
      CloudModelFailure.tooLong => l10n.lmHelpTooLong,
      CloudModelFailure.noAccount => l10n.lmHelpNoAccount,
      CloudModelFailure.backgroundCap => l10n.lmHelpBackgroundCap,
      CloudModelFailure.unknown => l10n.lmHelpUnknown,
    };

/// «Reintentando (2 de 4): …» con el motivo del fallo (F39).
String aiRetryingText(
  AppLocalizations l10n, {
  required int attempt,
  required int maxAttempts,
  required CloudModelFailure failure,
}) => l10n.aiRetrying(attempt, maxAttempts, aiFailureReason(l10n, failure));

/// [text] con la primera letra en mayúscula: los motivos van en minúscula
/// para ir en medio de una frase, y solos empiezan una.
String capitalized(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

/// La hora local de [at] para «hasta las …»: «4:00», o «4:00 de mañana» si
/// es mañana, o con la fecha si es más adelante.
String aiResetTime(BuildContext context, DateTime at, {DateTime? now}) {
  final l10n = AppLocalizations.of(context)!;
  final locale = Localizations.localeOf(context).toLanguageTag();
  final local = at.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  final time = DateFormat.Hm(locale).format(local);
  final days = DateUtils.dateOnly(
    local,
  ).difference(DateUtils.dateOnly(today)).inDays;
  if (days <= 0) return time;
  if (days == 1) return l10n.lmTimeTomorrow(time);
  return '${DateFormat.MMMd(locale).format(local)}, $time';
}

/// Una cantidad de tokens corta: «12 mil», «1,2 M».
String aiTokens(BuildContext context, int tokens) => NumberFormat.compact(
  locale: Localizations.localeOf(context).toLanguageTag(),
).format(tokens);
