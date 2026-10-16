import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_model_settings.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';

/// Lo elegido para la IA (F32), en las preferencias del teléfono: va con el
/// tema y el idioma, no con la bóveda —otro teléfono puede usar otro modelo—.
///
/// Va en una sola entrada JSON: elegir proveedor, cuenta y modelo cambia de a
/// varias cosas a la vez, y una sola escritura nunca deja la mitad.
class PrefsAiModelSettingsStore {
  PrefsAiModelSettingsStore({required SharedPreferences prefs})
    : _prefs = prefs;

  static const _key = 'ai_model_settings_v1';

  final SharedPreferences _prefs;

  /// Lo guardado; lo que no se entienda vuelve a lo de fábrica, de a un campo:
  /// un modelo ilegible no le borra a nadie sus cuentas elegidas.
  AiModelSettings read() {
    final raw = _prefs.getString(_key);
    if (raw == null) return const AiModelSettings();
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return const AiModelSettings();
    }
    if (json is! Map) return const AiModelSettings();

    Map<AiProvider, String> byProvider(Object? value) {
      if (value is! Map) return const {};
      return Map.unmodifiable({
        for (final entry in value.entries)
          if (AiProvider.fromStorageKey(entry.key as String?) case final p?)
            if (entry.value is String && (entry.value as String).isNotEmpty)
              p: entry.value as String,
      });
    }

    final cap = json['backgroundDailyCap'];
    return AiModelSettings(
      provider:
          AiProvider.fromStorageKey(json['provider'] as String?) ??
          AiProvider.fallback,
      activeAccounts: byProvider(json['activeAccounts']),
      models: byProvider(json['models']),
      autoSwitchAccounts: json['autoSwitchAccounts'] != false,
      backgroundDailyCap:
          cap is int && cap >= 0 && cap <= AiModelSettings.maxDailyCap
          ? cap
          : AiModelSettings.defaultBackgroundDailyCap,
    );
  }

  Future<void> write(AiModelSettings settings) => _prefs.setString(
    _key,
    jsonEncode({
      'provider': settings.provider.storageKey,
      'activeAccounts': {
        for (final e in settings.activeAccounts.entries)
          e.key.storageKey: e.value,
      },
      'models': {
        for (final e in settings.models.entries) e.key.storageKey: e.value,
      },
      'autoSwitchAccounts': settings.autoSwitchAccounts,
      'backgroundDailyCap': settings.backgroundDailyCap,
    }),
  );
}
