import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';

/// Los hechos fechados de la bóveda.
// ignore: one_member_abstracts
abstract interface class TimelineRepository {
  /// Los eventos de los elementos que cumplen [filter], en orden cronológico
  /// —ver `compareTimelineEvents`—, emitiendo de nuevo cada vez que algo
  /// cambia.
  ///
  /// [filter] es la misma consulta que entiende la biblioteca: el texto, las
  /// propiedades, el espacio. La línea de tiempo no tiene un segundo motor de
  /// filtros; ordenar y paginar de [filter] no se usan, porque el eje ordena
  /// y muestra todo.
  ///
  /// Solo cuentan las fechas de la categoría "Fecha del hecho": cuándo
  /// ocurrió lo que cuenta un elemento, no cuándo se capturó. Un elemento sin
  /// esa fecha no está en el eje, y uno con varias aparece una vez por fecha.
  Stream<List<TimelineEvent>> watchEvents(LibraryQuery filter);
}
