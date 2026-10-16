import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_model_settings.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/repositories/ai_account_repository.dart';
import 'package:sinapsis/features/ai_models/domain/repositories/ai_usage_ledger.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/ai_models/domain/services/quota_day.dart';

/// Lo que pasa con el modelo elegido (F32), con las mismas reglas con que
/// `CloudModelBackend` elige la cuenta: si ninguna de las que usaría tiene
/// cuota, no está listo, y la renovación es la más cercana de esas.
class AiLanguageModelReadiness {
  AiLanguageModelReadiness({
    required AiModelSettings Function() settings,
    required Future<bool> Function() gemmaReady,
    required AiAccountRepository accounts,
    required AiUsageLedger usage,
    required Clock clock,
  }) : _settings = settings,
       _gemmaReady = gemmaReady,
       _accounts = accounts,
       _usage = usage,
       _clock = clock;

  final AiModelSettings Function() _settings;
  final Future<bool> Function() _gemmaReady;
  final AiAccountRepository _accounts;
  final AiUsageLedger _usage;
  final Clock _clock;

  /// Ver [LanguageModelStatusCheck].
  Future<LanguageModelStatus> status({bool background = false}) async {
    final settings = _settings();
    final provider = settings.provider;
    if (!provider.isCloud) {
      return await _gemmaReady()
          ? LanguageModelReady(provider: provider)
          : const LanguageModelNeedsDownload();
    }

    final all = [
      for (final account in await _accounts.list())
        if (account.provider == provider) account,
    ];
    final withKey = <AiAccount>[
      for (final account in all)
        if (await _accounts.keyOf(account.id) != null) account,
    ];
    if (withKey.isEmpty) return LanguageModelNeedsAccount(provider: provider);

    final now = _clock();
    final activeId = settings.activeAccountOf(provider);
    final active = all.firstWhere(
      (a) => a.id == activeId,
      orElse: () => all.first,
    );
    // Sin el cambio automático, solo cuenta la elegida: si perdió su clave,
    // es como no tener cuenta.
    if (!settings.autoSwitchAccounts && !withKey.contains(active)) {
      return LanguageModelNeedsAccount(provider: provider);
    }
    final candidates = settings.autoSwitchAccounts ? withKey : [active];

    final usable = candidates.where(
      (a) => !_usage.usageOf(a.id, now: now).isExhaustedAt(now),
    );
    if (usable.isEmpty) {
      DateTime? resetsAt;
      var rejected = true;
      for (final account in candidates) {
        final usage = _usage.usageOf(account.id, now: now);
        final until = usage.exhaustedUntil;
        if (until != null && until.isAfter(now.toUtc())) {
          if (resetsAt == null || until.isBefore(resetsAt)) resetsAt = until;
        }
        if (usage.lastFailure != CloudModelFailure.invalidKey &&
            usage.lastFailure != CloudModelFailure.forbidden) {
          rejected = false;
        }
      }
      return LanguageModelOutOfQuota(
        provider: provider,
        accounts: candidates.length,
        resetsAt: resetsAt,
        keysRejected: rejected,
      );
    }

    if (background) {
      var used = 0;
      for (final account in all) {
        used += _usage.usageOf(account.id, now: now).backgroundRequests;
      }
      if (used >= settings.backgroundDailyCap) {
        return LanguageModelBackgroundCapReached(
          provider: provider,
          cap: settings.backgroundDailyCap,
          resetsAt: nextQuotaReset(now),
        );
      }
    }
    return LanguageModelReady(provider: provider);
  }
}
