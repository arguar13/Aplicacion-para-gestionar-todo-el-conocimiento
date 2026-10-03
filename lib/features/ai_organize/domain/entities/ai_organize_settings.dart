import 'package:flutter/foundation.dart';

/// Qué organiza sola la IA (F27): un interruptor por tipo y uno general, en
/// Ajustes › IA.
///
/// Arranca con todo prendido: es lo que el usuario pidió —"que se haga de
/// manera inteligente y automática"—, y cada cosa que hace la IA queda
/// marcada y se puede deshacer. Apagar un tipo no deshace lo ya hecho:
/// solo deja de hacer más.
@immutable
class AiOrganizeSettings {
  const AiOrganizeSettings({
    this.enabled = true,
    this.relations = true,
    this.flashcards = true,
    this.properties = true,
    this.space = true,
    this.reference = true,
    this.atlas = true,
    this.backfillWhileCharging = true,
  });

  /// El interruptor general: apagado, la cola de la IA no toma nada nuevo
  /// —"pausar la IA"—. Lo que ya está hecho sigue ahí.
  final bool enabled;

  /// Vínculos entre elementos.
  final bool relations;

  /// Tarjetas de repaso.
  final bool flashcards;

  /// Temas del vocabulario, etiquetas y propiedades.
  final bool properties;

  /// El tema (espacio) de cada elemento nuevo, si todavía no tiene.
  final bool space;

  /// Los datos vacíos de la referencia: autor, año, editorial…
  final bool reference;

  /// El árbol de temas del Atlas y sus notas mapa.
  final bool atlas;

  /// Pasar por la biblioteca que ya existía, solo con el teléfono cargando
  /// (decisión C).
  final bool backfillWhileCharging;

  AiOrganizeSettings copyWith({
    bool? enabled,
    bool? relations,
    bool? flashcards,
    bool? properties,
    bool? space,
    bool? reference,
    bool? atlas,
    bool? backfillWhileCharging,
  }) => AiOrganizeSettings(
    enabled: enabled ?? this.enabled,
    relations: relations ?? this.relations,
    flashcards: flashcards ?? this.flashcards,
    properties: properties ?? this.properties,
    space: space ?? this.space,
    reference: reference ?? this.reference,
    atlas: atlas ?? this.atlas,
    backfillWhileCharging: backfillWhileCharging ?? this.backfillWhileCharging,
  );

  @override
  bool operator ==(Object other) =>
      other is AiOrganizeSettings &&
      other.enabled == enabled &&
      other.relations == relations &&
      other.flashcards == flashcards &&
      other.properties == properties &&
      other.space == space &&
      other.reference == reference &&
      other.atlas == atlas &&
      other.backfillWhileCharging == backfillWhileCharging;

  @override
  int get hashCode => Object.hash(
    enabled,
    relations,
    flashcards,
    properties,
    space,
    reference,
    atlas,
    backfillWhileCharging,
  );
}

/// Cada interruptor de [AiOrganizeSettings], para cambiarlos con un solo
/// método.
enum AiOrganizeToggle {
  enabled,
  relations,
  flashcards,
  properties,
  space,
  reference,
  atlas,
  backfillWhileCharging;

  bool valueIn(AiOrganizeSettings settings) => switch (this) {
    AiOrganizeToggle.enabled => settings.enabled,
    AiOrganizeToggle.relations => settings.relations,
    AiOrganizeToggle.flashcards => settings.flashcards,
    AiOrganizeToggle.properties => settings.properties,
    AiOrganizeToggle.space => settings.space,
    AiOrganizeToggle.reference => settings.reference,
    AiOrganizeToggle.atlas => settings.atlas,
    AiOrganizeToggle.backfillWhileCharging => settings.backfillWhileCharging,
  };

  AiOrganizeSettings applyTo(AiOrganizeSettings settings, {required bool on}) =>
      switch (this) {
        AiOrganizeToggle.enabled => settings.copyWith(enabled: on),
        AiOrganizeToggle.relations => settings.copyWith(relations: on),
        AiOrganizeToggle.flashcards => settings.copyWith(flashcards: on),
        AiOrganizeToggle.properties => settings.copyWith(properties: on),
        AiOrganizeToggle.space => settings.copyWith(space: on),
        AiOrganizeToggle.reference => settings.copyWith(reference: on),
        AiOrganizeToggle.atlas => settings.copyWith(atlas: on),
        AiOrganizeToggle.backfillWhileCharging => settings.copyWith(
          backfillWhileCharging: on,
        ),
      };
}

/// En qué anda la cola de la IA (F27): lo que muestran Ajustes › IA y "Lo
/// que hizo la IA".
sealed class AiOrganizeStatus {
  const AiOrganizeStatus();
}

/// Sin nada pendiente.
final class AiOrganizeIdle extends AiOrganizeStatus {
  const AiOrganizeIdle();
}

/// Organizando [itemTitle]; [pending] cuántos esperan detrás, contando
/// la pasada por la biblioteca existente.
final class AiOrganizeWorking extends AiOrganizeStatus {
  const AiOrganizeWorking({required this.itemTitle, required this.pending});

  final String itemTitle;
  final int pending;
}

/// Pausada: por el interruptor general, o esperando el cargador para la
/// pasada por la biblioteca existente ([waitingForCharger]).
final class AiOrganizePaused extends AiOrganizeStatus {
  const AiOrganizePaused({
    required this.pending,
    this.waitingForCharger = false,
  });

  final int pending;
  final bool waitingForCharger;
}

/// Falta bajar el modelo de lenguaje o el de relaciones: sin ellos la IA no
/// puede organizar nada.
final class AiOrganizeModelMissing extends AiOrganizeStatus {
  const AiOrganizeModelMissing({
    required this.chatModelMissing,
    required this.embeddingModelMissing,
  });

  final bool chatModelMissing;
  final bool embeddingModelMissing;
}
