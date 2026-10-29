import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/features/ai_models/domain/entities/daily_quota.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_capability.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';

/// Lo que la app sabe y la persona eligió de cada cuenta para dibujar y para
/// la cuota (F43), en las preferencias del teléfono —como lo gastado de F32:
/// va con el teléfono, no con la bóveda—:
///
/// - si puede dibujar (lo recordado del primer pedido de imagen);
/// - su cuota diaria, la que fija la persona;
/// - qué modelos de imagen ofrece (la lista de su proveedor) y cuál se eligió.
///
/// Cada cosa, por id de cuenta: dos cuentas de Gemini pueden diferir (una con
/// facturación, otra sin).
class PrefsIllustrationStore {
  PrefsIllustrationStore({required SharedPreferences prefs}) : _prefs = prefs;

  static String _capabilityKey(String id) => 'ai_image_capability_$id';
  static String _quotaKey(String id) => 'ai_daily_quota_$id';
  static String _modelsKey(String id) => 'ai_image_models_$id';
  static String _modelKey(String id) => 'ai_image_model_$id';

  final SharedPreferences _prefs;
  final _changes = StreamController<void>.broadcast();

  /// Avisa cada vez que algo cambia.
  Stream<void> changes() => _changes.stream;

  Object? _json(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  Future<void> _write(String key, Object value) async {
    await _prefs.setString(key, jsonEncode(value));
    _changes.add(null);
  }

  /// Lo que se sabe de [accountId] para dibujar.
  ImageCapability capabilityOf(String accountId) =>
      ImageCapability.fromJson(_json(_capabilityKey(accountId))) ??
      const ImageCapability.untested();

  Future<void> setCapability(String accountId, ImageCapability capability) =>
      _write(_capabilityKey(accountId), capability.toJson());

  /// La cuota que fijó la persona para [accountId], o `null` si no fijó.
  DailyQuota? userQuotaOf(String accountId) {
    final quota = DailyQuota.fromJson(_json(_quotaKey(accountId)));
    return quota == null || quota.isEmpty ? null : quota;
  }

  /// Fija la cuota de [accountId]; vacía, vuelve a la estimada.
  Future<void> setUserQuota(String accountId, DailyQuota quota) async {
    if (quota.isEmpty) {
      await _prefs.remove(_quotaKey(accountId));
      _changes.add(null);
      return;
    }
    await _write(_quotaKey(accountId), quota.toJson());
  }

  /// Los modelos de imagen de [accountId] como se trajeron la última vez, y
  /// cuándo; `null` si nunca.
  ({DateTime fetchedAt, List<ImageModelInfo> models})? imageModelsOf(
    String accountId,
  ) {
    final json = _json(_modelsKey(accountId));
    if (json is! Map) return null;
    final fetched = DateTime.tryParse(json['fetchedAt'] as String? ?? '');
    final list = json['models'];
    if (fetched == null || list is! List) return null;
    return (
      fetchedAt: fetched.toUtc(),
      models: [
        for (final m in list)
          if (m is Map && m['id'] is String)
            ImageModelInfo(
              id: m['id'] as String,
              displayName: m['displayName'] as String? ?? m['id'] as String,
              route: m['route'] as String?,
            ),
      ],
    );
  }

  Future<void> setImageModels(
    String accountId,
    List<ImageModelInfo> models, {
    required DateTime fetchedAt,
  }) => _write(_modelsKey(accountId), {
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
    'models': [
      for (final m in models)
        {'id': m.id, 'displayName': m.displayName, 'route': ?m.route},
    ],
  });

  /// El modelo de imagen que eligió la persona para [accountId], o `null`
  /// (el recomendado).
  String? chosenImageModelOf(String accountId) {
    final value = _prefs.getString(_modelKey(accountId));
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> chooseImageModel(String accountId, String? model) async {
    if (model == null || model.isEmpty) {
      await _prefs.remove(_modelKey(accountId));
    } else {
      await _prefs.setString(_modelKey(accountId), model);
    }
    _changes.add(null);
  }

  /// Olvida todo de [accountId] (se borró la cuenta, o se le cambió la clave:
  /// lo que se sabía de la clave vieja ya no vale; la cuota sí se queda).
  Future<void> forget(String accountId, {bool keepQuota = false}) async {
    await _prefs.remove(_capabilityKey(accountId));
    await _prefs.remove(_modelsKey(accountId));
    if (!keepQuota) {
      await _prefs.remove(_quotaKey(accountId));
      await _prefs.remove(_modelKey(accountId));
    }
    _changes.add(null);
  }
}
