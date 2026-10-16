import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/features/ai_models/domain/entities/account_usage.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/repositories/ai_usage_ledger.dart';
import 'package:sinapsis/features/ai_models/domain/services/quota_day.dart';

/// [AiUsageLedger] en las preferencias del teléfono (F32): un número por
/// cuenta y por día de cuota, no un registro de cada pedido —lo único que se
/// muestra y se topea es el total de hoy—.
///
/// Solo se guarda el día en curso de cada cuenta: al empezar otro día, lo de
/// ayer se reemplaza. La marca de «agotada» dura hasta la hora que dijo el
/// proveedor, aunque cruce de día.
class PrefsAiUsageLedger implements AiUsageLedger {
  PrefsAiUsageLedger({required SharedPreferences prefs}) : _prefs = prefs;

  static String _key(String accountId) => 'ai_usage_$accountId';

  final SharedPreferences _prefs;
  final _changes = StreamController<void>.broadcast();

  AccountUsage? _stored(String accountId) {
    final raw = _prefs.getString(_key(accountId));
    if (raw == null) return null;
    try {
      return AccountUsage.fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  @override
  AccountUsage usageOf(String accountId, {required DateTime now}) {
    final day = quotaDayOf(now);
    final stored = _stored(accountId);
    if (stored == null) return AccountUsage(accountId: accountId, day: day);
    if (stored.day == day) return stored;
    // Otro día: los contadores vuelven a cero, pero una cuenta agotada hasta
    // más tarde (un tope de saldo, un aviso que cruza la medianoche) lo sigue.
    return AccountUsage(
      accountId: accountId,
      day: day,
      exhaustedUntil: stored.isExhaustedAt(now) ? stored.exhaustedUntil : null,
      lastFailure: stored.isExhaustedAt(now) ? stored.lastFailure : null,
    );
  }

  Future<void> _write(AccountUsage usage) async {
    await _prefs.setString(_key(usage.accountId), jsonEncode(usage.toJson()));
    _changes.add(null);
  }

  @override
  Stream<void> changes() => _changes.stream;

  @override
  Future<void> recordRequest(
    String accountId, {
    required DateTime now,
    required int inputTokens,
    required int outputTokens,
    required bool background,
  }) {
    final usage = usageOf(accountId, now: now);
    return _write(
      usage.copyWith(
        requests: usage.requests + 1,
        backgroundRequests: usage.backgroundRequests + (background ? 1 : 0),
        inputTokens: usage.inputTokens + (inputTokens > 0 ? inputTokens : 0),
        outputTokens:
            usage.outputTokens + (outputTokens > 0 ? outputTokens : 0),
      ),
    );
  }

  @override
  Future<void> markExhausted(
    String accountId, {
    required DateTime now,
    required DateTime until,
    required CloudModelFailure failure,
  }) {
    final usage = usageOf(accountId, now: now);
    return _write(
      usage.copyWith(exhaustedUntil: until.toUtc(), lastFailure: failure),
    );
  }

  @override
  Future<void> clearExhausted(String accountId, {required DateTime now}) {
    final usage = usageOf(accountId, now: now);
    if (usage.exhaustedUntil == null && usage.lastFailure == null) {
      return Future.value();
    }
    return _write(usage.copyWith(clearExhausted: true, clearFailure: true));
  }

  @override
  Future<void> forget(String accountId) async {
    await _prefs.remove(_key(accountId));
    _changes.add(null);
  }
}
