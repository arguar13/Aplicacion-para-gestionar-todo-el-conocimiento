import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';

/// En qué está una creación (F43): lo que dibuja su fila en «Lo creado».
enum CreationStatus {
  /// Espera en la cola: aparece enseguida, con su brillo y «Generando…».
  queued('queued'),

  /// La IA la está escribiendo.
  generating('generating'),

  /// Lista: tocarla abre su visor.
  ready('ready'),

  /// Falló: la fila dice por qué en una línea ([CreationFailure]) y ofrece
  /// «Reintentar».
  failed('failed');

  const CreationStatus(this.storageKey);

  final String storageKey;

  /// Si todavía no terminó: en la cola o generándose.
  bool get isPending => this == queued || this == generating;

  static CreationStatus? fromStorageKey(String key) {
    for (final status in values) {
      if (status.storageKey == key) return status;
    }
    return null;
  }
}

/// Por qué falló una creación: un motivo estable, que la interfaz dice con sus
/// palabras (`creationFailureMessage`). El detalle técnico va aparte, solo para
/// el registro.
enum CreationFailure {
  /// La persona la canceló.
  cancelled('cancelled'),

  /// El recorte no tenía nada que leer: sus documentos se borraron o no
  /// tienen texto.
  noSources('no_sources'),

  /// El modelo elegido no puede contestar ahora: sin descargar, sin clave, sin
  /// cuota.
  modelUnavailable('model_unavailable'),

  /// La IA contestó algo que no es el JSON pedido, ni siquiera después de
  /// pedirle una vez que lo corrija.
  unreadableReply('unreadable_reply'),

  /// La app se cerró a mitad tres veces, o llegó de otro dispositivo sin
  /// terminar: se reintenta a pedido.
  interrupted('interrupted'),

  /// Esta versión no sabe generar este tipo todavía.
  unsupported('unsupported'),

  /// Cualquier otra cosa.
  error('error');

  const CreationFailure(this.storageKey);

  final String storageKey;

  /// El motivo de [key]; uno que no se conoce es [error].
  static CreationFailure fromStorageKey(String key) {
    for (final failure in values) {
      if (failure.storageKey == key) return failure;
    }
    return error;
  }
}

/// En qué paso va una creación que se genera, para la línea de su fila. Lo
/// fino —la parte 3 de 12— va en [StudyCreation.progress].
enum CreationStep {
  /// Arma el material que entra en la ventana del modelo.
  preparing('preparing'),

  /// La IA escribe de una sola vez.
  writing('writing'),

  /// Por partes: cada parte da su borrador.
  readingParts('reading_parts'),

  /// Por partes: un último paso une los borradores.
  joining('joining'),

  /// Lo que el tipo hace después de la IA, como guardar las tarjetas del mazo.
  finishing('finishing'),

  /// Las ilustraciones con IA (decisión H), de a una, después del texto: la
  /// infografía y la presentación.
  illustrating('illustrating');

  const CreationStep(this.storageKey);

  final String storageKey;

  static CreationStep? fromStorageKey(String? key) {
    for (final step in values) {
      if (step.storageKey == key) return step;
    }
    return null;
  }
}

/// Una creación de «Lo creado» (F43): ver `StudyCreations`.
///
/// Las opciones y el contenido viajan como JSON: cada tipo sabe leer los suyos
/// ([options], [content]), y esta clase no conoce ningún esquema.
@immutable
class StudyCreation {
  const StudyCreation({
    required this.id,
    required this.kind,
    required this.scope,
    required this.languageCode,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.title,
    this.sourceIds = const [],
    this.options = const {},
    this.content,
    this.contentVersion = 1,
    this.failure,
    this.failureDetail,
    this.progress,
    this.step,
    this.runNow = false,
    this.attempts = 0,
    this.modelName,
    this.deletedAt,
  });

  final String id;
  final StudyCreationKind kind;

  /// El título que puso la IA o la persona; `null` mientras no hay —la fila
  /// muestra el nombre de su tipo—.
  final String? title;

  /// El recorte sobre el que se creó.
  final CreationScope scope;

  /// Los documentos procesados que de verdad se usaron, en el orden en que se
  /// leyeron. Un id que ya no es un procesado vivo es una «fuente borrada».
  final List<String> sourceIds;

  /// Lo elegido en la hoja de personalizar.
  final Map<String, Object?> options;

  /// El contenido, en el JSON del esquema de su tipo (decisión G); `null`
  /// mientras no está lista y siempre en las de extraer (decisión E).
  final String? content;

  /// La versión del esquema de [content].
  final int contentVersion;

  /// En qué idioma se pidió (`es`, `en`…).
  final String languageCode;

  final CreationStatus status;

  /// Por qué falló, solo con [CreationStatus.failed].
  final CreationFailure? failure;

  /// El detalle técnico de [failure], para el registro.
  final String? failureDetail;

  /// Cuánto va, de 0 a 1, mientras se genera; `null` si no se sabe.
  final double? progress;

  /// En qué paso va, mientras se genera.
  final CreationStep? step;

  /// Si se pidió con «Generar ahora» (el turno de la persona) y no con
  /// «Generar más tarde» (la cola de fondo).
  final bool runNow;

  /// Cuántas veces se empezó sin terminar porque la app se cerró.
  final int attempts;

  /// Con qué modelo se escribió.
  final String? modelName;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Cuándo se mandó a la papelera; `null` si está viva.
  final DateTime? deletedAt;

  bool get isTrashed => deletedAt != null;

  /// [content] leído como JSON; `null` si no hay o no se entiende.
  Object? get decodedContent {
    final raw = content;
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is StudyCreation &&
      other.id == id &&
      other.kind == kind &&
      other.title == title &&
      other.scope == scope &&
      listEquals(other.sourceIds, sourceIds) &&
      mapEquals(other.options, options) &&
      other.content == content &&
      other.contentVersion == contentVersion &&
      other.languageCode == languageCode &&
      other.status == status &&
      other.failure == failure &&
      other.failureDetail == failureDetail &&
      other.progress == progress &&
      other.step == step &&
      other.runNow == runNow &&
      other.attempts == attempts &&
      other.modelName == modelName &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt;

  @override
  int get hashCode => Object.hashAll([
    id,
    kind,
    title,
    scope,
    Object.hashAll(sourceIds),
    content,
    contentVersion,
    languageCode,
    status,
    failure,
    progress,
    step,
    runNow,
    attempts,
    modelName,
    updatedAt,
    deletedAt,
  ]);

  @override
  String toString() =>
      'StudyCreation($id, ${kind.storageKey}, ${status.storageKey}, '
      '${scope.storageKey})';
}

/// Lo que se pide al crear una (F43): lo que sale de la hoja de personalizar.
@immutable
class CreationRequest {
  const CreationRequest({
    required this.kind,
    required this.scope,
    required this.sourceIds,
    this.options = const {},
    this.languageCode = 'es',
    this.runNow = true,
  });

  final StudyCreationKind kind;
  final CreationScope scope;

  /// Los documentos del recorte que quedaron tildados en «Fuentes».
  final List<String> sourceIds;

  /// Lo elegido en la hoja, como JSON: cada tipo arma el suyo.
  final Map<String, Object?> options;

  final String languageCode;

  /// «Generar ahora» (`true`) o «Generar más tarde» (`false`).
  final bool runNow;
}
