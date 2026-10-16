import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/ai_models/data/repositories/prefs_ai_model_settings_store.dart';
import 'package:sinapsis/features/ai_models/data/repositories/prefs_ai_usage_ledger.dart';
import 'package:sinapsis/features/ai_models/data/repositories/secure_ai_account_repository.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_model_settings.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';

class _CountingIds implements IdGenerator {
  var _n = 0;

  @override
  String next() => 'id${++_n}';
}

/// Las cuentas, lo gastado y lo elegido, guardados (F32).
void main() {
  group('las cuentas, en el almacén seguro', () {
    late SecureAiAccountRepository repository;
    late DateTime now;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      now = DateTime.utc(2026, 10, 16, 12);
      repository = SecureAiAccountRepository(
        ids: _CountingIds(),
        clock: () => now,
      );
    });

    test('agregar guarda el nombre en la lista y la clave aparte', () async {
      final account = await repository.add(
        provider: AiProvider.gemini,
        key: '  AIzaClave1  ',
        label: 'armando@gmail.com',
      );

      expect(await repository.list(), [account]);
      expect(await repository.keyOf(account.id), 'AIzaClave1');

      // La lista, tal como queda guardada, no lleva ninguna clave.
      final stored = await const FlutterSecureStorage().readAll();
      final list = stored['ai_accounts_v1']!;
      expect(list, contains('armando@gmail.com'));
      expect(list, isNot(contains('AIzaClave1')));
      expect(stored['ai_key_${account.id}'], 'AIzaClave1');
    });

    test(
      'sin nombre le pone «Cuenta N», contando las de ese proveedor',
      () async {
        final first = await repository.add(
          provider: AiProvider.gemini,
          key: 'k1',
        );
        final other = await repository.add(
          provider: AiProvider.openAi,
          key: 'k2',
        );
        final second = await repository.add(
          provider: AiProvider.gemini,
          key: 'k3',
          label: '   ',
        );

        expect(first.label, 'Cuenta 1');
        expect(other.label, 'Cuenta 1');
        expect(second.label, 'Cuenta 2');
      },
    );

    test('una clave vacía no se acepta', () async {
      expect(
        () => repository.add(provider: AiProvider.gemini, key: '   '),
        throwsArgumentError,
      );
      expect(await repository.list(), isEmpty);
    });

    test('en el orden en que se agregaron', () async {
      final a = await repository.add(provider: AiProvider.gemini, key: 'k1');
      now = now.add(const Duration(minutes: 1));
      final b = await repository.add(provider: AiProvider.gemini, key: 'k2');

      expect(await repository.list(), [a, b]);
    });

    test('renombrar, cambiar la clave y borrar', () async {
      final a = await repository.add(provider: AiProvider.gemini, key: 'k1');
      final b = await repository.add(provider: AiProvider.gemini, key: 'k2');

      await repository.rename(a.id, '  Personal ');
      await repository.rename(b.id, '   ');
      await repository.replaceKey(a.id, ' nueva ');
      await repository.remove(b.id);

      final list = await repository.list();
      expect(list.map((x) => x.label), ['Personal']);
      expect(await repository.keyOf(a.id), 'nueva');
      expect(await repository.keyOf(b.id), isNull);
      expect(
        await const FlutterSecureStorage().containsKey(key: 'ai_key_${b.id}'),
        isFalse,
      );
    });

    test('muchos cambios seguidos sin esperar no se pisan', () async {
      await Future.wait([
        for (var i = 0; i < 10; i++)
          repository.add(provider: AiProvider.gemini, key: 'k$i'),
      ]);

      final list = await repository.list();
      expect(list, hasLength(10));
      expect(list.map((a) => a.id).toSet(), hasLength(10));
    });

    test('mirar avisa cada cambio, empezando por lo que hay', () async {
      final seen = <int>[];
      final sub = repository.watch().listen((l) => seen.add(l.length));
      await pumpEventQueue();
      await repository.add(provider: AiProvider.gemini, key: 'k1');
      final b = await repository.add(provider: AiProvider.gemini, key: 'k2');
      await repository.remove(b.id);
      await pumpEventQueue();
      await sub.cancel();

      expect(seen, [0, 1, 2, 1]);
    });

    test('una lista ilegible se lee vacía, sin romper', () async {
      FlutterSecureStorage.setMockInitialValues({'ai_accounts_v1': '{no'});
      expect(await repository.list(), isEmpty);
    });
  });

  group('lo gastado, por cuenta y por día de cuota', () {
    late PrefsAiUsageLedger ledger;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      ledger = PrefsAiUsageLedger(prefs: await SharedPreferences.getInstance());
    });

    final day = DateTime.utc(2026, 10, 16, 15);

    test('suma pedidos y tokens, y aparte los de la IA de fondo', () async {
      await ledger.recordRequest(
        'a1',
        now: day,
        inputTokens: 1000,
        outputTokens: 200,
        background: false,
      );
      await ledger.recordRequest(
        'a1',
        now: day,
        inputTokens: 500,
        outputTokens: -1,
        background: true,
      );

      final usage = ledger.usageOf('a1', now: day);
      expect(usage.requests, 2);
      expect(usage.backgroundRequests, 1);
      expect(usage.inputTokens, 1500);
      expect(usage.outputTokens, 200);
      expect(ledger.usageOf('otra', now: day).requests, 0);
    });

    test('al empezar otro día de cuota, vuelve a cero', () async {
      await ledger.recordRequest(
        'a1',
        now: day,
        inputTokens: 10,
        outputTokens: 10,
        background: false,
      );
      // 16/10 15:00 UTC → la cuota se renueva el 17 a las 7:00 UTC.
      expect(
        ledger.usageOf('a1', now: DateTime.utc(2026, 10, 17, 6)).requests,
        1,
      );
      expect(
        ledger.usageOf('a1', now: DateTime.utc(2026, 10, 17, 7)).requests,
        0,
      );
    });

    test(
      'agotada hasta lo que dijo el proveedor, aunque cruce de día',
      () async {
        await ledger.markExhausted(
          'a1',
          now: day,
          until: DateTime.utc(2026, 10, 18),
          failure: CloudModelFailure.quotaExhausted,
        );

        final nextDay = DateTime.utc(2026, 10, 17, 9);
        final usage = ledger.usageOf('a1', now: nextDay);
        expect(usage.isExhaustedAt(nextDay), isTrue);
        expect(usage.lastFailure, CloudModelFailure.quotaExhausted);

        await ledger.clearExhausted('a1', now: nextDay);
        expect(
          ledger.usageOf('a1', now: nextDay).isExhaustedAt(nextDay),
          isFalse,
        );
      },
    );

    test('olvidar una cuenta borra lo suyo y avisa', () async {
      var changes = 0;
      final sub = ledger.changes().listen((_) => changes++);
      await ledger.recordRequest(
        'a1',
        now: day,
        inputTokens: 1,
        outputTokens: 1,
        background: false,
      );
      await ledger.forget('a1');
      await pumpEventQueue();
      await sub.cancel();

      expect(ledger.usageOf('a1', now: day).requests, 0);
      expect(changes, 2);
    });
  });

  group('lo elegido, en las preferencias', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('sin nada guardado: lo de fábrica', () {
      expect(
        PrefsAiModelSettingsStore(prefs: prefs).read(),
        const AiModelSettings(),
      );
    });

    test('ida y vuelta', () async {
      final store = PrefsAiModelSettingsStore(prefs: prefs);
      final settings =
          const AiModelSettings(
                provider: AiProvider.anthropic,
                autoSwitchAccounts: false,
                backgroundDailyCap: 40,
              )
              .withActiveAccount(AiProvider.gemini, 'a1')
              .withModel(AiProvider.anthropic, 'claude-sonnet-5-5');

      await store.write(settings);

      expect(PrefsAiModelSettingsStore(prefs: prefs).read(), settings);
    });

    test(
      'lo que no se entiende vuelve a lo de fábrica de a un campo',
      () async {
        await prefs.setString(
          'ai_model_settings_v1',
          jsonEncode({
            'provider': 'futuro',
            'activeAccounts': {'gemini': 'a1', 'nadie': 'x', 'openai': ''},
            'models': 'no es un mapa',
            'autoSwitchAccounts': 'sí',
            'backgroundDailyCap': -5,
          }),
        );

        final read = PrefsAiModelSettingsStore(prefs: prefs).read();
        expect(read.provider, AiProvider.gemini);
        expect(read.activeAccounts, {AiProvider.gemini: 'a1'});
        expect(read.models, isEmpty);
        expect(read.autoSwitchAccounts, isTrue);
        expect(
          read.backgroundDailyCap,
          AiModelSettings.defaultBackgroundDailyCap,
        );
      },
    );

    test('un JSON roto: lo de fábrica', () async {
      await prefs.setString('ai_model_settings_v1', '{roto');
      expect(
        PrefsAiModelSettingsStore(prefs: prefs).read(),
        const AiModelSettings(),
      );
    });
  });
}
