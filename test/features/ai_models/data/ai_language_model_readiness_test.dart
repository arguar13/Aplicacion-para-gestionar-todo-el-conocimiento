import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/ai_models/data/repositories/prefs_ai_usage_ledger.dart';
import 'package:sinapsis/features/ai_models/data/repositories/secure_ai_account_repository.dart';
import 'package:sinapsis/features/ai_models/data/services/ai_language_model_readiness.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_model_settings.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/ai_models/domain/services/quota_day.dart';

class _Ids implements IdGenerator {
  var _n = 0;

  @override
  String next() => 'cuenta${++_n}';
}

void main() {
  late SecureAiAccountRepository accounts;
  late PrefsAiUsageLedger usage;
  late AiModelSettings settings;
  late bool gemmaReady;
  late DateTime now;
  late AiLanguageModelReadiness readiness;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 10, 16, 15);
    accounts = SecureAiAccountRepository(ids: _Ids(), clock: () => now);
    usage = PrefsAiUsageLedger(prefs: await SharedPreferences.getInstance());
    settings = const AiModelSettings();
    gemmaReady = false;
    readiness = AiLanguageModelReadiness(
      settings: () => settings,
      gemmaReady: () async => gemmaReady,
      accounts: accounts,
      usage: usage,
      clock: () => now,
    );
  });

  Future<AiAccount> add(String key, {AiProvider? provider}) => accounts.add(
    provider: provider ?? AiProvider.gemini,
    key: key,
    label: key,
  );

  Future<void> exhaust(
    AiAccount account, {
    Duration until = const Duration(hours: 2),
    CloudModelFailure failure = CloudModelFailure.quotaExhausted,
  }) => usage.markExhausted(
    account.id,
    now: now,
    until: now.add(until),
    failure: failure,
  );

  test('con Gemma, depende de que esté bajado', () async {
    settings = const AiModelSettings(provider: AiProvider.gemma);
    expect(await readiness.status(), isA<LanguageModelNeedsDownload>());
    gemmaReady = true;
    expect(
      await readiness.status(),
      isA<LanguageModelReady>().having(
        (s) => s.provider,
        'provider',
        AiProvider.gemma,
      ),
    );
  });

  test('en la nube sin ninguna cuenta del proveedor, falta cargar una '
      '(Gemma bajado no cuenta, y las cuentas de otro proveedor '
      'tampoco)', () async {
    gemmaReady = true;
    await add('sk-otra', provider: AiProvider.openAi);
    expect(
      await readiness.status(),
      isA<LanguageModelNeedsAccount>().having(
        (s) => s.provider,
        'provider',
        AiProvider.gemini,
      ),
    );
    await add('clave-1');
    expect(await readiness.status(), isA<LanguageModelReady>());
  });

  test('con todas las cuentas agotadas no está listo, y dice la renovación '
      'más cercana', () async {
    final a = await add('clave-1');
    final b = await add('clave-2');
    await exhaust(a, until: const Duration(hours: 3));
    expect(await readiness.status(), isA<LanguageModelReady>());
    await exhaust(b, until: const Duration(hours: 1));
    final status = await readiness.status();
    expect(
      status,
      isA<LanguageModelOutOfQuota>()
          .having((s) => s.accounts, 'accounts', 2)
          .having(
            (s) => s.resetsAt,
            'resetsAt',
            now.add(const Duration(hours: 1)),
          )
          .having((s) => s.keysRejected, 'keysRejected', isFalse),
    );
  });

  test('sin el cambio automático, solo cuenta la elegida', () async {
    final a = await add('clave-1');
    await add('clave-2');
    settings = const AiModelSettings(autoSwitchAccounts: false);
    await exhaust(a);
    expect(
      await readiness.status(),
      isA<LanguageModelOutOfQuota>().having((s) => s.accounts, 'accounts', 1),
    );
  });

  test('si lo que las deja afuera es la clave, lo dice', () async {
    final a = await add('clave-1');
    await exhaust(a, failure: CloudModelFailure.invalidKey);
    expect(
      await readiness.status(),
      isA<LanguageModelOutOfQuota>().having(
        (s) => s.keysRejected,
        'keysRejected',
        isTrue,
      ),
    );
  });

  test('la IA de fondo ve su tope del día; la persona no', () async {
    final a = await add('clave-1');
    settings = const AiModelSettings(backgroundDailyCap: 2);
    for (var i = 0; i < 2; i++) {
      await usage.recordRequest(
        a.id,
        now: now,
        inputTokens: 1,
        outputTokens: 1,
        background: true,
      );
    }
    expect(await readiness.status(), isA<LanguageModelReady>());
    expect(
      await readiness.status(background: true),
      isA<LanguageModelBackgroundCapReached>()
          .having((s) => s.cap, 'cap', 2)
          .having((s) => s.resetsAt, 'resetsAt', nextQuotaReset(now)),
    );
  });
}
