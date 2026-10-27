import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';

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
    this.dates = true,
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

  /// Los hechos fechados de cada texto para la línea de tiempo (F40). Prendido
  /// por lo mismo que los demás: es lo pedido, lo que pone lleva su cita y su
  /// ✨, y se saca con deshacer la pasada. Un texto sin fechas no llega ni a
  /// pedirle nada al modelo.
  final bool dates;

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
    bool? dates,
    bool? backfillWhileCharging,
  }) => AiOrganizeSettings(
    enabled: enabled ?? this.enabled,
    relations: relations ?? this.relations,
    flashcards: flashcards ?? this.flashcards,
    properties: properties ?? this.properties,
    space: space ?? this.space,
    reference: reference ?? this.reference,
    atlas: atlas ?? this.atlas,
    dates: dates ?? this.dates,
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
      other.dates == dates &&
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
    dates,
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
  dates,
  backfillWhileCharging;

  bool valueIn(AiOrganizeSettings settings) => switch (this) {
    AiOrganizeToggle.enabled => settings.enabled,
    AiOrganizeToggle.relations => settings.relations,
    AiOrganizeToggle.flashcards => settings.flashcards,
    AiOrganizeToggle.properties => settings.properties,
    AiOrganizeToggle.space => settings.space,
    AiOrganizeToggle.reference => settings.reference,
    AiOrganizeToggle.atlas => settings.atlas,
    AiOrganizeToggle.dates => settings.dates,
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
        AiOrganizeToggle.dates => settings.copyWith(dates: on),
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

/// De dónde salió el elemento que la IA está organizando: lo que la cola
/// toma, en su orden.
enum AiWorkSource {
  /// Lo pidió la persona, desde el elemento.
  requested,

  /// Es nuevo: una fuente que terminó de procesarse o una nota que se dejó
  /// de escribir.
  fresh,

  /// Una nota ya organizada que cambió mucho.
  changedNote,

  /// La pasada por la biblioteca que ya existía, con el cargador (decisión
  /// C).
  existingLibrary,

  /// Solo las tarjetas que pidió la persona desde Repasar (F30), sin esperar
  /// el cargador.
  flashcardsRequest,

  /// Solo las fechas que pidió la persona para la línea de tiempo (F40), sin
  /// esperar el cargador: «Organizar con IA» de la línea o «Buscar fechas con
  /// IA» del detalle.
  datesRequest,
}

/// Organizando [itemTitle], que salió de [source]; [pending] cuántos esperan
/// detrás, contando la pasada por la biblioteca existente.
final class AiOrganizeWorking extends AiOrganizeStatus {
  const AiOrganizeWorking({
    required this.itemTitle,
    required this.pending,
    required this.source,
  });

  final String itemTitle;
  final int pending;
  final AiWorkSource source;
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

/// Falta el modelo de lenguaje o el de relaciones: sin ellos la IA no puede
/// organizar nada. Al de lenguaje le falta bajarlo (Gemma) o, si se eligió
/// uno en la nube, una clave de [keyFor] (F32).
final class AiOrganizeModelMissing extends AiOrganizeStatus {
  const AiOrganizeModelMissing({
    required this.chatModelMissing,
    required this.embeddingModelMissing,
    this.keyFor,
  });

  final bool chatModelMissing;
  final bool embeddingModelMissing;

  /// El proveedor en la nube al que le falta una clave; `null` si lo que
  /// falta es bajar Gemma.
  final AiProvider? keyFor;
}

/// Por qué la IA de fondo espera al modelo de lenguaje en la nube (F32).
enum AiModelWait {
  /// Ninguna cuenta tiene cuota: vuelve a la hora de la renovación.
  quota,

  /// La IA de fondo usó sus pedidos del día; lo que pide la persona sigue.
  backgroundCap,

  /// Ninguna clave anda: hasta que la persona cargue o arregle una.
  keysRejected,

  /// No hay conexión: vuelve a probar sola en unos minutos.
  offline,

  /// El proveedor está saturado o pide esperar: vuelve a probar sola.
  busy,

  /// La espera venció o la respuesta se cortó, y no se arregló reintentando
  /// (F39): vuelve a probar sola.
  interrupted,

  /// El modelo elegido ya no existe: hasta que la persona elija otro.
  modelGone,
}

/// La IA de fondo espera al modelo de lenguaje en la nube por [reason]
/// (F32), sin perder nada: lo que estaba organizando se retoma donde quedó.
/// Sigue sola a las [resumesAt], si se sabe; [cap] es el tope del día, con
/// [AiModelWait.backgroundCap].
final class AiOrganizeWaitingForModel extends AiOrganizeStatus {
  const AiOrganizeWaitingForModel({
    required this.reason,
    required this.pending,
    this.resumesAt,
    this.cap,
  });

  final AiModelWait reason;
  final int pending;
  final DateTime? resumesAt;
  final int? cap;
}
