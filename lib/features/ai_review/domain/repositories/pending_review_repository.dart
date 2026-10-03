import 'package:sinapsis/features/ai_review/domain/entities/pending_review_item.dart';

/// Qué hay «Para revisar» (F27), en toda la bóveda.
///
/// Lo dudoso de la IA queda como sugerencia pendiente en la cola de siempre
/// —vínculos, propiedades y datos de la referencia—, y `SuggestionRepository`
/// la lee elemento por elemento, que es lo que necesitan la Bandeja y el
/// detalle. «Lo que hizo la IA» y Ajustes necesitan la otra mitad: de qué
/// elementos hay que hablar, y cuántas son, sin abrir una consulta por cada
/// elemento de la bóveda.
///
/// Los duplicados no entran: fusionar borra un elemento y tienen su propia
/// pantalla (decisión A de F27: siguen como aviso). Un vínculo propuesto
/// hacia algo que está en la papelera tampoco, igual que en
/// `SuggestionRepository.watchPendingSuggestions`.
abstract interface class PendingReviewRepository {
  /// Los elementos vivos con sugerencias pendientes de vínculo, propiedad o
  /// referencia, el de la más reciente primero, actualizándose solos.
  Stream<List<PendingReviewItem>> watchItemsWithPendingReview();

  /// Cuántas sugerencias hay para revisar en total, actualizándose solo: lo
  /// que muestra Ajustes › IA junto a «Lo que hizo la IA». Un solo número,
  /// sin traer ni agrupar las filas.
  Stream<int> watchPendingReviewCount();
}
