import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/correction_subject.dart';

/// Un valor que vale al corregir algo (F33): un tipo de vínculo, un valor de
/// la categoría, un tema. [id] es lo que se guarda en la corrección; [label],
/// cómo se lo nombra.
@immutable
class ReviewOption {
  const ReviewOption({required this.id, required this.label});

  final String id;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is ReviewOption && other.id == id && other.label == label;

  @override
  int get hashCode => Object.hash(id, label);

  @override
  String toString() => 'ReviewOption($id: $label)';
}

/// Algo que hizo la IA en un elemento y sigue siendo suyo, como se le da a
/// revisar a otro modelo (F33, «Revisar con otro modelo»): un vínculo, una
/// etiqueta, el tema, un dato de la referencia o la introducción de una nota
/// mapa. Las tarjetas tienen su propio revisor.
///
/// [before] es lo que va en la corrección como «antes»: lo que el modelo ve,
/// y lo que tiene que seguir igual para poder aceptarla.
@immutable
class ReviewableAiThing {
  const ReviewableAiThing({
    required this.subject,
    required this.subjectId,
    required this.before,
    required this.aiRunId,
    this.model,
    this.label,
    this.options = const [],
    this.canFix = true,
    this.canRemove = true,
    this.relatedItemId,
  });

  final CorrectionSubject subject;
  final String subjectId;
  final Map<String, String> before;

  /// La pasada que lo hizo, y su modelo: al revisar toda la biblioteca, un
  /// modelo no revisa lo suyo.
  final String aiRunId;
  final String? model;

  /// Qué es, cuando no lo dicen los datos: en un vínculo, el título del otro
  /// elemento.
  final String? label;

  /// Lo único que vale al corregirlo; vacío si es un texto libre (un dato de
  /// la referencia, una introducción).
  final List<ReviewOption> options;

  /// Si se puede corregir —una etiqueta que no es de texto, no— y si se
  /// puede sacar —una introducción, no—.
  final bool canFix;
  final bool canRemove;

  /// En un vínculo, el otro elemento: el revisor lo ve para juzgarlo.
  final String? relatedItemId;

  @override
  bool operator ==(Object other) =>
      other is ReviewableAiThing &&
      other.subject == subject &&
      other.subjectId == subjectId &&
      mapEquals(other.before, before) &&
      other.aiRunId == aiRunId &&
      other.model == model &&
      other.label == label &&
      listEquals(other.options, options) &&
      other.canFix == canFix &&
      other.canRemove == canRemove &&
      other.relatedItemId == relatedItemId;

  @override
  int get hashCode => Object.hash(
    subject,
    subjectId,
    Object.hashAllUnordered(before.entries.map((e) => '${e.key}=${e.value}')),
    aiRunId,
    model,
    label,
    Object.hashAll(options),
    canFix,
    canRemove,
    relatedItemId,
  );

  @override
  String toString() =>
      'ReviewableAiThing(${subject.name} $subjectId: $before'
      '${label == null ? '' : ' «$label»'})';
}
