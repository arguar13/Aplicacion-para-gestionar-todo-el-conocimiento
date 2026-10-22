import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';

/// Una marca de estudio (F36): una oración del resumen o de la síntesis, o
/// una palabra clave, en el rango `[start, end)` del texto de su forma.
@immutable
class StudyMark {
  const StudyMark({
    required this.id,
    required this.kind,
    required this.origin,
    required this.start,
    required this.end,
  });

  final String id;
  final StudyMarkKind kind;

  /// La IA, al analizar, o la persona, al elegir una palabra clave a mano.
  final ContentOrigin origin;

  final int start;
  final int end;

  /// Si la marca está entera dentro de `[start, end)`.
  bool isWithin(int start, int end) => this.start >= start && this.end <= end;

  @override
  bool operator ==(Object other) =>
      other is StudyMark &&
      other.id == id &&
      other.kind == kind &&
      other.origin == origin &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(id, kind, origin, start, end);

  @override
  String toString() => 'StudyMark($kind, $start, $end, $origin)';
}

/// Lo estudiado de un texto (F36): sus marcas, en orden, y hasta dónde se
/// analizó.
@immutable
class DocumentStudy {
  const DocumentStudy({
    required this.marks,
    required this.analyzedUntil,
    required this.complete,
  });

  /// Un texto que todavía no se empezó a analizar.
  static const notStarted = DocumentStudy(
    marks: [],
    analyzedUntil: 0,
    complete: false,
  );

  /// Ordenadas por dónde empiezan.
  final List<StudyMark> marks;

  /// Hasta qué posición del texto está analizado.
  final int analyzedUntil;

  /// Si ya no queda nada por analizar.
  final bool complete;

  /// Si se analizó al menos una parte.
  bool get started => complete || analyzedUntil > 0;

  /// Las marcas de [kind], en orden.
  List<StudyMark> of(StudyMarkKind kind) => [
    for (final mark in marks)
      if (mark.kind == kind) mark,
  ];

  @override
  bool operator ==(Object other) =>
      other is DocumentStudy &&
      listEquals(other.marks, marks) &&
      other.analyzedUntil == analyzedUntil &&
      other.complete == complete;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(marks), analyzedUntil, complete);
}
