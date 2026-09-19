import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/timeline/domain/services/timeline_axis.dart';

part 'timeline_event.freezed.dart';

/// Un hecho fechado sobre el eje: la "Fecha del hecho" de un elemento.
///
/// Un elemento con dos fechas —una fundación y una caída— son dos eventos
/// con el mismo `itemId`: el eje muestra hechos, no elementos.
///
/// Las posiciones ([from], [to]) están en el eje continuo de
/// `timeline_axis.dart`. Como la fecha tiene precisión, el evento no es un
/// punto sino un tramo: "476" ocupa ese año entero y "siglo V" cien.
@freezed
sealed class TimelineEvent with _$TimelineEvent {
  const factory TimelineEvent({
    required String itemId,
    required String title,
    required HistoricalDate date,

    /// De qué es el elemento: para distinguir una fuente de una nota.
    required SourceKind sourceKind,

    /// El subtipo, solo si el elemento es una nota.
    NoteKind? noteKind,
  }) = _TimelineEvent;

  const TimelineEvent._();

  /// Dónde empieza el tramo que cubre la fecha.
  double get from => axisStart(date.rangeStart);

  /// Dónde termina: nunca antes de [from], ni siquiera para un día.
  double get to => axisEnd(date.rangeEnd);

  /// `true` si la fecha es de década o siglo: se sabe el tramo en que
  /// ocurrió, no el momento. Se dibuja distinto de un año exacto, que es un
  /// dato.
  bool get isPeriod =>
      date.precision == DatePrecision.decade ||
      date.precision == DatePrecision.century;

  /// Cuánto se corre cada extremo por un "circa": la mitad del tramo.
  ///
  /// Es una convención de dibujo, no un dato que la fuente haya dado: la
  /// base solo dice que la fecha es aproximada, no por cuánto. La mitad de
  /// la unidad de la precisión —medio año en "circa 476", cincuenta en
  /// "circa siglo V"— alcanza para que se vea que los bordes son difusos sin
  /// prometer una incertidumbre que nadie midió.
  double get fuzz => date.isCirca ? (to - from) / 2 : 0;

  /// Dónde llega el evento hacia el pasado, contando el borde difuso.
  double get reachFrom => from - fuzz;

  /// Dónde llega hacia el futuro, contando el borde difuso.
  double get reachTo => to + fuzz;
}
