import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/timeline/domain/services/timeline_axis.dart';

part 'timeline_event.freezed.dart';

/// Un hecho sobre el eje, de uno de los dos orígenes (F40):
///
/// - la "Fecha del hecho" de un elemento: cuándo pasó lo que cuenta el
///   elemento entero. Se llama como el elemento y [datedEventId] es `null`;
/// - un hecho fechado dentro de un documento (`DatedEvent`): trae su propio
///   [title], su cita y, si es un tramo, su [end].
///
/// Un elemento con dos fechas —una fundación y una caída— son dos eventos
/// con el mismo `itemId`: el eje muestra hechos, no elementos.
///
/// Las posiciones ([from], [to]) están en el eje continuo de
/// `timeline_axis.dart`. Como la fecha tiene precisión, el evento no es un
/// punto sino un tramo: "476" ocupa ese año entero y "siglo V" cien; y uno
/// con [end] va de donde empieza [date] a donde termina [end].
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

    /// El hecho fechado de donde sale (F40), o `null` si es la «Fecha del
    /// hecho» del elemento. Con él se edita y se quita el hecho.
    String? datedEventId,

    /// Cuándo termina, si el hecho fechado es un tramo («1914–1918»).
    HistoricalDate? end,

    /// El título del elemento, cuando [title] es el del hecho. `null` en la
    /// «Fecha del hecho», donde [title] ya es el del elemento.
    String? itemTitle,

    /// El texto del que sale la cita de un hecho fechado y dónde está en él:
    /// lo que hace falta para abrir el documento justo ahí. Las posiciones
    /// son `null` si el hecho no tiene cita o el texto cambió y ya no está.
    String? renditionId,
    int? startOffset,
    int? endOffset,

    /// La cita del hecho, copiada.
    String? excerpt,

    /// Quién puso el hecho fechado; `null` en la «Fecha del hecho».
    ContentOrigin? origin,
  }) = _TimelineEvent;

  const TimelineEvent._();

  /// Dónde empieza el tramo que cubre la fecha.
  double get from => axisStart(date.rangeStart);

  /// Dónde termina: nunca antes de [from], ni siquiera para un día. Con [end],
  /// donde termina esa fecha.
  double get to => axisEnd((end ?? date).rangeEnd);

  /// Si es un hecho fechado dentro de un documento y no la «Fecha del hecho»
  /// del elemento.
  bool get isDatedEvent => datedEventId != null;

  /// Si es un tramo con fin propio («1914–1918»), no un momento con la
  /// amplitud de su precisión.
  bool get isRange => end != null;

  /// Si lo puso la IA y nadie lo editó desde entonces.
  bool get isAi => origin == ContentOrigin.ai;

  /// Si se sabe dónde está la cita en el texto.
  bool get hasAnchor => renditionId != null && startOffset != null;

  /// El título del elemento del que sale, sea cual sea el origen.
  String get documentTitle => itemTitle ?? title;

  /// Cuándo pasó, tal como se escribe: la fecha y, si es un tramo, su fin
  /// después de un guion largo («1914 – 1918»).
  String get dateLabel =>
      end == null ? date.label : '${date.label} – ${end!.label}';

  /// `true` si la fecha es de década o siglo: se sabe el tramo en que
  /// ocurrió, no el momento. Se dibuja distinto de un año exacto, que es un
  /// dato. Un tramo con fin propio es otra cosa: se sabe de cuándo a cuándo.
  bool get isPeriod =>
      end == null &&
      (date.precision == DatePrecision.decade ||
          date.precision == DatePrecision.century);

  /// Cuánto se corre cada extremo por un "circa": la mitad del tramo.
  ///
  /// Es una convención de dibujo, no un dato que la fuente haya dado: la
  /// base solo dice que la fecha es aproximada, no por cuánto. La mitad de
  /// la unidad de la precisión —medio año en "circa 476", cincuenta en
  /// "circa siglo V"— alcanza para que se vea que los bordes son difusos sin
  /// prometer una incertidumbre que nadie midió. Es la de [date], no la del
  /// tramo entero: «circa 1500–1520» tiene los bordes borrosos por un año,
  /// no por diez.
  double get fuzz => date.isCirca ? (axisEnd(date.rangeEnd) - from) / 2 : 0;

  /// Dónde llega el evento hacia el pasado, contando el borde difuso.
  double get reachFrom => from - fuzz;

  /// Dónde llega hacia el futuro, contando el borde difuso.
  double get reachTo => to + fuzz;
}
