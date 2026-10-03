import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';

/// Dónde quedó una fuente respecto de la Bandeja (F28): lo que se ve y se
/// filtra de [ItemState], sin sus matices internos.
///
/// Antes de F28 triar cambiaba un estado que ninguna pantalla mostraba: lo
/// triado seguía en la Biblioteca sin ninguna marca, y parecía que la Bandeja
/// se lo había tragado. Esto es lo que lo vuelve a hacer encontrable —la
/// sección «Bandeja» de los filtros y el chip del detalle—.
///
/// Solo las fuentes pasan por la Bandeja: una nota no se tría, su progreso se
/// mide con su madurez.
enum InboxStatus {
  /// Esperando en la Bandeja que alguien decida qué hacer con ella.
  pending,

  /// Ya se decidió que vale la pena —o se trabajó del todo—.
  triaged,

  /// Se decidió que no vale la pena. No se borró: sigue en la Biblioteca.
  discarded;

  /// Los estados de trabajo que cuentan como este. Destilar es triar y además
  /// sacarle las notas: para quien busca «lo triado», también es triado.
  Set<ItemState> get itemStates => switch (this) {
    InboxStatus.pending => const {ItemState.processed},
    InboxStatus.triaged => const {ItemState.triaged, ItemState.distilled},
    InboxStatus.discarded => const {ItemState.discarded},
  };

  /// Dónde está, respecto de la Bandeja, un elemento de tipo [kind] en el
  /// estado [state]. `null` si no tiene nada que ver con la Bandeja: una nota,
  /// o una fuente que todavía se está procesando —`captured`—, que llega a la
  /// Bandeja recién cuando termina.
  static InboxStatus? of(ItemKind kind, ItemState state) {
    if (kind != ItemKind.source) return null;
    for (final status in values) {
      if (status.itemStates.contains(state)) return status;
    }
    return null;
  }
}
