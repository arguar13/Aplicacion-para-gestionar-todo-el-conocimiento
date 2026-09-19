import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';

/// Un año de calendario ("44 a.C.", "476") con la precisión que se pida.
HistoricalDate dateOf(
  int year, {
  bool bce = false,
  bool circa = false,
  DatePrecision precision = DatePrecision.year,
}) => HistoricalDate(
  year: year,
  precision: precision,
  isBce: bce,
  isCirca: circa,
);

/// Un evento de prueba. Cada [id] es un elemento distinto salvo que un caso
/// quiera justamente dos fechas para el mismo.
TimelineEvent eventAt(
  String id,
  HistoricalDate date, {
  String? title,
  SourceKind sourceKind = SourceKind.manualNote,
  NoteKind? noteKind,
}) => TimelineEvent(
  itemId: id,
  title: title ?? 'Evento $id',
  date: date,
  sourceKind: sourceKind,
  noteKind: noteKind,
);
