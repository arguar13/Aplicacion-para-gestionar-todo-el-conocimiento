import 'package:sinapsis/features/ai_models/domain/entities/account_usage.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';

/// Lo que gastó cada cuenta en el día de cuota (F32), y cuándo dijo el
/// proveedor que se terminó. Lo cuenta la app: es lo que se muestra al lado
/// de cada cuenta, lo que topea la IA de fondo y lo que decide a qué cuenta
/// pasar cuando una se queda sin cuota.
abstract interface class AiUsageLedger {
  /// Lo de [accountId] en el día de cuota de [now] (vacío si no se usó).
  AccountUsage usageOf(String accountId, {required DateTime now});

  /// Avisa cada vez que algo cambia.
  Stream<void> changes();

  /// Un pedido que salió bien, con lo que el proveedor contó.
  Future<void> recordRequest(
    String accountId, {
    required DateTime now,
    required int inputTokens,
    required int outputTokens,
    required bool background,
  });

  /// El proveedor dijo que [accountId] no tiene cuota hasta [until].
  Future<void> markExhausted(
    String accountId, {
    required DateTime now,
    required DateTime until,
    required CloudModelFailure failure,
  });

  /// [accountId] volvió a andar: ya no se la toma por agotada.
  Future<void> clearExhausted(String accountId, {required DateTime now});

  /// Olvida todo lo de [accountId] (se borró la cuenta).
  Future<void> forget(String accountId);
}
