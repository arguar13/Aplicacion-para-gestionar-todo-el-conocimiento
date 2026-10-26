import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/features/timeline/domain/entities/historical_date_order.dart';

/// Un hecho fechado que se propone para la línea de tiempo (F40), todavía sin
/// guardar: lo que contó el modelo de un documento, con el lugar del texto de
/// donde sale.
///
/// La cita [start]–[end] es un rango `[inicio, fin)` del texto **entero** del
/// elemento, el que se lee y se resalta: lo que permite abrir el documento
/// justo ahí. [excerpt] es ese tramo tal cual está en el texto.
@immutable
class DatedEventDraft {
  DatedEventDraft({
    required this.date,
    required this.title,
    required this.start,
    required this.end,
    required this.excerpt,
    this.endDate,
  }) : assert(title.isNotEmpty, 'Un hecho tiene título.'),
       assert(
         endDate == null || endDate.compareStart(date) >= 0,
         'El fin de un hecho no puede ser anterior a su inicio.',
       ),
       assert(start >= 0 && end > start, 'La cita tiene que tener texto.'),
       assert(end - start == excerpt.length, 'La cita es el tramo del texto.');

  /// Cuándo ocurrió, o cuándo empezó si [endDate] no es `null`.
  final HistoricalDate date;

  /// Cuándo terminó, si duró: «1914–1918». Nunca antes de [date].
  final HistoricalDate? endDate;

  /// El hecho, en pocas palabras: «Publica El origen de las especies».
  final String title;

  /// Dónde empieza la cita en el texto entero.
  final int start;

  /// Dónde termina la cita en el texto entero (exclusivo).
  final int end;

  /// La cita, textual.
  final String excerpt;

  @override
  bool operator ==(Object other) =>
      other is DatedEventDraft &&
      other.date == date &&
      other.endDate == endDate &&
      other.title == title &&
      other.start == start &&
      other.end == end &&
      other.excerpt == excerpt;

  @override
  int get hashCode => Object.hash(date, endDate, title, start, end, excerpt);

  @override
  String toString() =>
      'DatedEventDraft(${date.label}'
      '${endDate == null ? '' : ' – ${endDate!.label}'}, $title, '
      '[$start, $end))';
}
