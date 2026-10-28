import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';

/// Los hechos de la bóveda sobre el eje: las fechas de los elementos y los
/// hechos fechados dentro de los documentos.
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
  /// Hay dos orígenes (F40), y los dos pasan por [filter]:
  ///
  /// - las fechas de la categoría "Fecha del hecho": cuándo ocurrió lo que
  ///   cuenta un elemento entero, no cuándo se capturó. Un elemento sin esa
  ///   fecha no aporta, y uno con varias aparece una vez por fecha;
  /// - los hechos fechados dentro de un documento (`DatedEvent`), cada uno
  ///   con su título, su cita y, si es un tramo, su fin.
  ///
  /// Lee el corpus de [filter] (F41, paso 6): la línea de tiempo pide lo
  /// procesado —y los hechos que la persona escribe a mano en una nota suya—;
  /// el calendario de la Biblioteca, sus fuentes y sus notas.
  ///
  /// Lo que está en la papelera no aparece, y cualquiera de las dos fuentes
  /// que cambie hace emitir de nuevo.
  Stream<List<TimelineEvent>> watchEvents(LibraryQuery filter);
}
