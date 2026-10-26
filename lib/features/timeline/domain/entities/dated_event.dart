import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';

part 'dated_event.freezed.dart';

/// Un hecho fechado dentro de un documento (F40): «1859: publica *El origen de
/// las especies*». Ver `DatedEvents`.
///
/// No es la «Fecha del hecho» del elemento —esa es de todo el elemento y no
/// sabe qué pasó—: un libro tiene muchos de estos, cada uno con su título, su
/// fecha y la cita del texto de la que sale.
@freezed
sealed class DatedEvent with _$DatedEvent {
  const factory DatedEvent({
    required String id,
    required String itemId,

    /// Qué pasó, corto.
    required String title,

    /// Cuándo empieza (o cuándo pasó, si no es un tramo).
    required HistoricalDate date,

    /// Quién lo puso.
    required ContentOrigin origin,
    required DateTime createdAt,
    required DateTime updatedAt,

    /// El texto del que sale la cita. `null` si el hecho se puso a mano sin
    /// cita.
    String? renditionId,

    /// Cuándo termina, si el hecho es un tramo («1914–1918»). El «circa» es
    /// del hecho entero y está en [date]: el de este extremo siempre es el
    /// mismo.
    HistoricalDate? end,

    /// Dónde está la cita en el texto de [renditionId]. `null` si el hecho no
    /// tiene cita, o si el texto se volvió a extraer y la cita ya no está.
    int? startOffset,
    int? endOffset,

    /// La cita, copiada.
    String? excerpt,

    /// La pasada de la IA que lo puso, si sigue siendo de la IA y se sabe cuál.
    String? aiRunId,
  }) = _DatedEvent;

  const DatedEvent._();

  /// Si lo puso la IA y nadie lo editó desde entonces.
  bool get isAi => origin == ContentOrigin.ai;

  /// Si el hecho es un tramo y no un momento.
  bool get isRange => end != null;

  /// Si se sabe dónde está la cita en el texto: lo que hace falta para abrir
  /// el documento justo ahí.
  bool get hasAnchor => renditionId != null && startOffset != null;
}
