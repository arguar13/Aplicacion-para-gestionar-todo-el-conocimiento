import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/entities/account_usage.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_model_settings.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/repositories/ai_account_repository.dart';
import 'package:sinapsis/features/ai_models/domain/services/quota_day.dart';

/// El dominio de las cuentas y la cuota de la IA en la nube (F32).
void main() {
  group('el día de la cuota, en la hora del Pacífico', () {
    test('en invierno es UTC−8: las 7:59 UTC todavía son el día anterior', () {
      expect(quotaDayOf(DateTime.utc(2026, 1, 15, 7, 59)), '2026-01-14');
      expect(quotaDayOf(DateTime.utc(2026, 1, 15, 8)), '2026-01-15');
    });

    test('en verano es UTC−7: el cambio es a las 7:00 UTC', () {
      expect(quotaDayOf(DateTime.utc(2026, 7, 15, 6, 59)), '2026-07-14');
      expect(quotaDayOf(DateTime.utc(2026, 7, 15, 7)), '2026-07-15');
    });

    test('el verano empieza el segundo domingo de marzo, 2:00 de allá', () {
      // 2026: el segundo domingo de marzo es el 8. 2:00 PST = 10:00 UTC.
      expect(isPacificDaylightTime(DateTime.utc(2026, 3, 8, 9, 59)), isFalse);
      expect(isPacificDaylightTime(DateTime.utc(2026, 3, 8, 10)), isTrue);
      // 2027: el 14.
      expect(isPacificDaylightTime(DateTime.utc(2027, 3, 14, 9, 59)), isFalse);
      expect(isPacificDaylightTime(DateTime.utc(2027, 3, 14, 10)), isTrue);
    });

    test('termina el primer domingo de noviembre a las 2:00 de allá', () {
      // 2026: el 1. 2:00 PDT = 9:00 UTC.
      expect(isPacificDaylightTime(DateTime.utc(2026, 11, 1, 8, 59)), isTrue);
      expect(isPacificDaylightTime(DateTime.utc(2026, 11, 1, 9)), isFalse);
      // 2027: el 7.
      expect(isPacificDaylightTime(DateTime.utc(2027, 11, 7, 8, 59)), isTrue);
      expect(isPacificDaylightTime(DateTime.utc(2027, 11, 7, 9)), isFalse);
    });

    test('la cuota se renueva en la próxima medianoche de allá', () {
      // 16 de octubre (verano): medianoche del 17 = 7:00 UTC.
      expect(
        nextQuotaReset(DateTime.utc(2026, 10, 16, 15)),
        DateTime.utc(2026, 10, 17, 7),
      );
      // Enero (invierno): 8:00 UTC.
      expect(
        nextQuotaReset(DateTime.utc(2026, 1, 15, 20)),
        DateTime.utc(2026, 1, 16, 8),
      );
      // Justo a la medianoche, la que viene es la siguiente.
      expect(
        nextQuotaReset(DateTime.utc(2026, 1, 16, 8)),
        DateTime.utc(2026, 1, 17, 8),
      );
    });

    test('el día que cambia la hora, la medianoche que sigue usa la hora '
        'nueva', () {
      // El sábado 31 de octubre de 2026 a la tarde (verano); la medianoche del
      // domingo 1 todavía es de verano (la hora cambia a las 2:00): 7:00 UTC.
      expect(
        nextQuotaReset(DateTime.utc(2026, 10, 31, 20)),
        DateTime.utc(2026, 11, 1, 7),
      );
      // El domingo 1 a la tarde (ya invierno): la del lunes 2, 8:00 UTC.
      expect(
        nextQuotaReset(DateTime.utc(2026, 11, 1, 20)),
        DateTime.utc(2026, 11, 2, 8),
      );
      // El sábado 7 de marzo de 2026 (invierno); la del domingo 8 es antes del
      // cambio de las 2:00: 8:00 UTC.
      expect(
        nextQuotaReset(DateTime.utc(2026, 3, 7, 20)),
        DateTime.utc(2026, 3, 8, 8),
      );
    });

    test('un instante local se pasa a UTC antes de decidir', () {
      final local = DateTime.utc(2026, 1, 15, 8).toLocal();
      expect(quotaDayOf(local), '2026-01-15');
    });
  });

  group('una cuenta', () {
    final account = AiAccount(
      id: 'a1',
      provider: AiProvider.gemini,
      label: 'armando@gmail.com',
      addedAt: DateTime.utc(2026, 10, 16, 12),
    );

    test('ida y vuelta por JSON', () {
      expect(AiAccount.fromJson(account.toJson()), account);
    });

    test('lo que no se entiende se descarta, sin romper', () {
      expect(AiAccount.fromJson(null), isNull);
      expect(AiAccount.fromJson({'id': 'x', 'provider': 'nadie'}), isNull);
      expect(
        AiAccount.fromJson({'id': '', 'provider': 'gemini', 'label': 'x'}),
        isNull,
      );
      expect(
        AiAccount.fromJson({'id': 'x', 'provider': 'gemini', 'label': 3}),
        isNull,
      );
    });

    test('la clave se muestra sin revelarla', () {
      expect(maskedKey('AIzaSyD-1234567890abcdk3Fq'), 'AIza…k3Fq');
      expect(maskedKey('  AIzaSyD-1234567890abcdk3Fq  '), 'AIza…k3Fq');
      expect(maskedKey('corta'), '••••');
    });
  });

  group('los proveedores', () {
    test('se guardan con una clave estable, y lo desconocido no rompe', () {
      for (final provider in AiProvider.values) {
        expect(AiProvider.fromStorageKey(provider.storageKey), provider);
      }
      expect(AiProvider.fromStorageKey('futuro'), isNull);
      expect(AiProvider.fromStorageKey(null), isNull);
    });

    test('Gemini es el de fábrica; solo Gemma corre en el teléfono', () {
      expect(AiProvider.fallback, AiProvider.gemini);
      expect(AiProvider.values.where((p) => !p.isCloud), [AiProvider.gemma]);
      expect(AiProvider.gemma.keysUrl, isNull);
      expect(AiProvider.gemini.keysUrl, contains('aistudio.google.com'));
    });
  });

  group('lo elegido', () {
    test('de fábrica: Gemini, cambio automático de cuenta y tope de fondo', () {
      const settings = AiModelSettings();
      expect(settings.provider, AiProvider.gemini);
      expect(settings.autoSwitchAccounts, isTrue);
      expect(
        settings.backgroundDailyCap,
        AiModelSettings.defaultBackgroundDailyCap,
      );
    });

    test('la cuenta y el modelo de cada proveedor, por separado', () {
      final settings = const AiModelSettings()
          .withActiveAccount(AiProvider.gemini, 'a1')
          .withActiveAccount(AiProvider.openAi, 'o1')
          .withModel(AiProvider.gemini, 'gemini-3.8-flash');

      expect(settings.activeAccountOf(AiProvider.gemini), 'a1');
      expect(settings.activeAccountOf(AiProvider.openAi), 'o1');
      expect(settings.activeAccountOf(AiProvider.anthropic), isNull);
      expect(settings.modelOf(AiProvider.gemini), 'gemini-3.8-flash');

      final back = settings
          .withActiveAccount(AiProvider.gemini, null)
          .withModel(AiProvider.gemini, '');
      expect(back.activeAccountOf(AiProvider.gemini), isNull);
      expect(back.modelOf(AiProvider.gemini), isNull);
      expect(back.activeAccountOf(AiProvider.openAi), 'o1');
    });

    test('iguales si eligen lo mismo, aunque se armen en otro orden', () {
      final a = const AiModelSettings()
          .withActiveAccount(AiProvider.gemini, 'a1')
          .withActiveAccount(AiProvider.openAi, 'o1');
      final b = const AiModelSettings()
          .withActiveAccount(AiProvider.openAi, 'o1')
          .withActiveAccount(AiProvider.gemini, 'a1');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == a.withModel(AiProvider.gemini, 'x'), isFalse);
    });
  });

  group('lo gastado', () {
    test('ida y vuelta por JSON, con la cuota agotada', () {
      final usage = AccountUsage(
        accountId: 'a1',
        day: '2026-10-16',
        requests: 12,
        backgroundRequests: 5,
        inputTokens: 34000,
        outputTokens: 2100,
        exhaustedUntil: DateTime.utc(2026, 10, 17, 7),
        lastFailure: CloudModelFailure.quotaExhausted,
      );
      expect(AccountUsage.fromJson(usage.toJson()), usage);
    });

    test('agotada hasta la hora que dijo el proveedor, y no después', () {
      final usage = AccountUsage(
        accountId: 'a1',
        day: '2026-10-16',
        exhaustedUntil: DateTime.utc(2026, 10, 17, 7),
      );
      expect(usage.isExhaustedAt(DateTime.utc(2026, 10, 17, 6, 59)), isTrue);
      expect(usage.isExhaustedAt(DateTime.utc(2026, 10, 17, 7)), isFalse);
      expect(
        const AccountUsage(
          accountId: 'a1',
          day: 'x',
        ).isExhaustedAt(DateTime.utc(2026)),
        isFalse,
      );
    });

    test('lo ilegible cuenta como cero, no rompe', () {
      final usage = AccountUsage.fromJson({
        'accountId': 'a1',
        'day': '2026-10-16',
        'requests': -3,
        'inputTokens': 'mucho',
        'lastFailure': 'algoNuevo',
      })!;
      expect(usage.requests, 0);
      expect(usage.inputTokens, 0);
      expect(usage.lastFailure, isNull);
    });
  });
}
