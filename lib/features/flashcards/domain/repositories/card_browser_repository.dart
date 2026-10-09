import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/flashcards/domain/entities/card_browser_query.dart';
import 'package:sinapsis/features/flashcards/domain/entities/card_browser_row.dart';

/// Mirar, buscar y ordenar todas las tarjetas (F31, ola 2, decisión 72): lo que
/// «Mis tarjetas» lee, y las dos escrituras en lote que `FlashcardRepository`
/// no tiene —volver a nueva y borrar muchas—. Pausar, reanudar y posponer ya
/// están en `FlashcardRepository` y se usan de allí.
///
/// Nunca devuelve tarjetas de un elemento en la papelera: una tarjeta que no se
/// puede repasar no se muestra, y volvería a aparecer con el elemento si se lo
/// restaura.
abstract interface class CardBrowserRepository {
  /// Cuántas tarjetas cumplen [query].
  Future<Either<Failure, int>> count(CardBrowserQuery query);

  /// Una página de [query]: [limit] renglones desde la posición [offset] del
  /// orden pedido. El orden es TOTAL —desempata por identificador—, así que dos
  /// páginas seguidas nunca repiten ni se saltean una tarjeta mientras la base
  /// no cambie.
  Future<Either<Failure, List<CardBrowserRow>>> page(
    CardBrowserQuery query, {
    required int offset,
    required int limit,
  });

  /// Los identificadores de TODAS las que cumplen [query], en el orden pedido:
  /// para «seleccionar las N» sin traer las tarjetas.
  Future<Either<Failure, List<String>>> ids(CardBrowserQuery query);

  /// Cuántas hay en cada estado dentro del recorte y el texto de [query] (su
  /// propio `status` se ignora), para rotular los filtros.
  Future<Either<Failure, Map<CardBrowserStatus, int>>> statusCounts(
    CardBrowserQuery query,
  );

  /// Avisa cada vez que cambia algo que puede cambiar una lista: las tarjetas,
  /// sus elementos o aquello de lo que está hecho un recorte.
  Stream<void> changes();

  /// Vuelve las tarjetas [ids] a NUEVAS: facilidad 2,5, sin intervalo, sin
  /// repeticiones, sin paso de aprendizaje, sin haberse contestado y para
  /// estudiar ya. Conserva su pausa, su contenido y su historial de repasos
  /// (las estadísticas pasadas no se reescriben). Es todo o nada: si una
  /// falla, ninguna cambia. Devuelve cuántas cambió.
  Future<Either<Failure, int>> resetSchedule(Iterable<String> ids);

  /// Borra las tarjetas [ids] para siempre, con sus opciones y su historial de
  /// repasos (en cascada). No hay papelera de tarjetas: la papelera de la app
  /// es de elementos, y borrar una tarjeta es lo que ya hace
  /// `FlashcardRepository.delete`. Todo o nada. Devuelve cuántas borró.
  Future<Either<Failure, int>> deleteMany(Iterable<String> ids);
}
