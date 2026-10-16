import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_wire.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_model_settings.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_info.dart';

/// Cuánto se confía en la lista guardada antes de volver a pedirla: los
/// proveedores sacan modelos nuevos cada pocos meses, no cada hora.
const kModelListMaxAge = Duration(days: 3);

/// Los modelos de cada proveedor en la nube (F32), como los devolvió su lista,
/// guardados en las preferencias para no pedirlos en cada respuesta, y cuál
/// usar: el que eligió la persona o, si no eligió, el recomendado.
class CloudModelCatalog {
  CloudModelCatalog({
    required SharedPreferences prefs,
    required Map<AiProvider, CloudWire> wires,
    required Clock clock,
  }) : _prefs = prefs,
       _wires = wires,
       _clock = clock;

  static String _key(AiProvider provider) =>
      'ai_models_cache_${provider.storageKey}';

  final SharedPreferences _prefs;
  final Map<AiProvider, CloudWire> _wires;
  final Clock _clock;

  CloudWire _wire(AiProvider provider) {
    final wire = _wires[provider];
    if (wire == null) {
      throw ArgumentError.value(provider, 'provider', 'No es de la nube');
    }
    return wire;
  }

  ({DateTime fetchedAt, List<CloudModelInfo> models})? _stored(
    AiProvider provider,
  ) {
    final raw = _prefs.getString(_key(provider));
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final fetched = DateTime.tryParse(json['fetchedAt'] as String? ?? '');
      final list = json['models'];
      if (fetched == null || list is! List) return null;
      return (
        fetchedAt: fetched,
        models: [
          for (final m in list)
            if (m is Map && m['id'] is String)
              CloudModelInfo(
                id: m['id'] as String,
                displayName: m['displayName'] as String? ?? m['id'] as String,
                inputTokens: m['inputTokens'] as int?,
                outputTokens: m['outputTokens'] as int?,
              ),
        ],
      );
    } on FormatException {
      return null;
    }
  }

  /// La última lista que se trajo de [provider] (vacía si nunca).
  List<CloudModelInfo> cached(AiProvider provider) =>
      _stored(provider)?.models ?? const [];

  /// Vuelve a pedir la lista con [key] y la guarda.
  Future<List<CloudModelInfo>> refresh(
    AiProvider provider, {
    required String key,
  }) async {
    final models = await _wire(provider).listModels(key);
    await _prefs.setString(
      _key(provider),
      jsonEncode({
        'fetchedAt': _clock().toUtc().toIso8601String(),
        'models': [
          for (final m in models)
            {
              'id': m.id,
              'displayName': m.displayName,
              'inputTokens': ?m.inputTokens,
              'outputTokens': ?m.outputTokens,
            },
        ],
      }),
    );
    return models;
  }

  /// El recomendado de lo que hay guardado, o `null` si no hay lista.
  String? recommended(AiProvider provider) =>
      _wire(provider).recommendedModel(cached(provider));

  /// Lo que se sabe de [model], si está en la lista guardada.
  CloudModelInfo? info(AiProvider provider, String model) {
    for (final m in cached(provider)) {
      if (m.id == model) return m;
    }
    return null;
  }

  /// El modelo con que se escribe: el elegido en [settings] o, si no hay, el
  /// recomendado de la lista —que se vuelve a pedir con [key] si es vieja o
  /// no está—. Si la lista no se puede traer pero había una guardada, sirve
  /// la guardada.
  Future<String> resolve(
    AiProvider provider,
    AiModelSettings settings, {
    required String key,
  }) async {
    final chosen = settings.modelOf(provider);
    if (chosen != null) return chosen;
    final stored = _stored(provider);
    var models = stored?.models ?? const <CloudModelInfo>[];
    final stale =
        stored == null ||
        _clock().toUtc().difference(stored.fetchedAt) > kModelListMaxAge;
    if (models.isEmpty || stale) {
      try {
        models = await refresh(provider, key: key);
      } on CloudModelException {
        if (models.isEmpty) rethrow;
      }
    }
    final recommended = _wire(provider).recommendedModel(models);
    if (recommended == null) {
      throw const CloudModelException(
        CloudModelFailure.modelNotFound,
        detail: 'El proveedor no devolvió ningún modelo de texto',
      );
    }
    return recommended;
  }
}
