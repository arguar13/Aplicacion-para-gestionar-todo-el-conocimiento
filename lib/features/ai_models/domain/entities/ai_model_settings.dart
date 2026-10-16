import 'package:meta/meta.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';

/// Lo elegido para la IA (F32): qué proveedor escribe, con qué cuenta y qué
/// modelo de cada uno, y cómo se reparte la cuota.
///
/// Es una preferencia de este teléfono, no un dato de la bóveda: va con el
/// tema y el idioma, en las preferencias. Las claves no están acá.
@immutable
class AiModelSettings {
  const AiModelSettings({
    this.provider = AiProvider.fallback,
    this.activeAccounts = const {},
    this.models = const {},
    this.autoSwitchAccounts = true,
    this.backgroundDailyCap = defaultBackgroundDailyCap,
  }) : assert(
         backgroundDailyCap >= 0 && backgroundDailyCap <= maxDailyCap,
         'Fuera de rango',
       );

  /// Pedidos por día que puede hacer la IA de fondo con un proveedor en la
  /// nube, como mucho. Deja cuota para lo que pide la persona.
  static const defaultBackgroundDailyCap = 100;

  /// El tope más alto que se acepta: en la práctica, «sin tope».
  static const maxDailyCap = 99999;

  /// Quién escribe todas las respuestas.
  final AiProvider provider;

  /// La cuenta en uso de cada proveedor en la nube, por su id. Sin entrada: la
  /// primera que tenga.
  final Map<AiProvider, String> activeAccounts;

  /// El modelo elegido de cada proveedor, por su código («gemini-3.8-flash»).
  /// Sin entrada: el que la app recomienda de la lista del proveedor.
  final Map<AiProvider, String> models;

  /// Al quedarse sin cuota una cuenta, pasar sola a la siguiente con cuota y
  /// avisar (decisión B de F32, elegida por el usuario).
  final bool autoSwitchAccounts;

  /// Ver [defaultBackgroundDailyCap].
  final int backgroundDailyCap;

  /// La cuenta en uso de [of], o `null` si no se eligió ninguna.
  String? activeAccountOf(AiProvider of) => activeAccounts[of];

  /// El modelo elegido de [of], o `null` si se deja el recomendado.
  String? modelOf(AiProvider of) => models[of];

  AiModelSettings copyWith({
    AiProvider? provider,
    Map<AiProvider, String>? activeAccounts,
    Map<AiProvider, String>? models,
    bool? autoSwitchAccounts,
    int? backgroundDailyCap,
  }) => AiModelSettings(
    provider: provider ?? this.provider,
    activeAccounts: activeAccounts ?? this.activeAccounts,
    models: models ?? this.models,
    autoSwitchAccounts: autoSwitchAccounts ?? this.autoSwitchAccounts,
    backgroundDailyCap: backgroundDailyCap ?? this.backgroundDailyCap,
  );

  /// Lo mismo con [accountId] como la cuenta en uso de [of].
  AiModelSettings withActiveAccount(AiProvider of, String? accountId) {
    final next = Map<AiProvider, String>.of(activeAccounts);
    if (accountId == null) {
      next.remove(of);
    } else {
      next[of] = accountId;
    }
    return copyWith(activeAccounts: Map.unmodifiable(next));
  }

  /// Lo mismo con [model] como el modelo de [of] (`null`: el recomendado).
  AiModelSettings withModel(AiProvider of, String? model) {
    final next = Map<AiProvider, String>.of(models);
    if (model == null || model.isEmpty) {
      next.remove(of);
    } else {
      next[of] = model;
    }
    return copyWith(models: Map.unmodifiable(next));
  }

  @override
  bool operator ==(Object other) =>
      other is AiModelSettings &&
      other.provider == provider &&
      _sameMap(other.activeAccounts, activeAccounts) &&
      _sameMap(other.models, models) &&
      other.autoSwitchAccounts == autoSwitchAccounts &&
      other.backgroundDailyCap == backgroundDailyCap;

  @override
  int get hashCode => Object.hash(
    provider,
    Object.hashAllUnordered(
      activeAccounts.entries.map((e) => (e.key, e.value)),
    ),
    Object.hashAllUnordered(models.entries.map((e) => (e.key, e.value))),
    autoSwitchAccounts,
    backgroundDailyCap,
  );

  static bool _sameMap(Map<AiProvider, String> a, Map<AiProvider, String> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
}
