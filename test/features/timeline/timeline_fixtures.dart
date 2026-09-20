import 'dart:math';

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

/// Hechos repartidos entre 3000 a.C. y 2025 d.C. —diez mil, por defecto—, de
/// cualquier precisión: años, meses, días, décadas, siglos y aproximados. Son
/// los mismos de una corrida a otra: el generador tiene semilla.
List<TimelineEvent> tenThousandTimelineEvents({int total = 10000}) {
  final random = Random(2026);
  return [
    for (var i = 0; i < total; i++)
      () {
        final bce = random.nextInt(3) == 0;
        return eventAt(
          'e${i.toString().padLeft(5, '0')}',
          HistoricalDate(
            year: 1 + random.nextInt(bce ? 3000 : 2025),
            precision: switch (random.nextInt(10)) {
              0 => DatePrecision.century,
              1 || 2 => DatePrecision.decade,
              3 || 4 => DatePrecision.day,
              5 => DatePrecision.month,
              _ => DatePrecision.year,
            },
            month: 1 + random.nextInt(12),
            day: 1 + random.nextInt(28),
            isBce: bce,
            isCirca: random.nextInt(8) == 0,
          ),
        );
      }(),
  ];
}
