import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/inbox/domain/entities/note_reference.dart';

/// El lado del espejo `item`/`source`/`note` (ver la decisión sobre F3 en
/// docs/arquitectura.md) que sirve a la Bandeja de entrada: qué queda por
/// triar, cómo se transiciona un elemento, y qué notas vivas existen para
/// vincular. Primer lector y escritor real de esas tablas desde que
/// existen —F1 solo las pobló, nunca las leyó—.
abstract interface class InboxRepository {
  /// Los ids de las fuentes en `processed`, de más vieja a más nueva
  /// (`updatedAt` ascendente: la que lleva más tiempo esperando triaje va
  /// primero). Filtra `kind == ItemKind.source` — las notas no se trían,
  /// su progreso se mide con [watchNoteMaturity], no con este flujo.
  Stream<List<String>> watchPendingIds();

  /// Cambia el estado de un elemento. Sin una máquina de estados
  /// completa: los únicos llamadores hoy son las 3 acciones de la
  /// Bandeja (`processed → discarded`, `processed → triaged`).
  Future<Either<Failure, Unit>> transitionState({
    required String itemId,
    required ItemState to,
  });

  /// Las notas vivas que existen, para elegir una al "vincular a nota
  /// viva". [searchText] filtra por título, sin distinguir mayúsculas.
  Stream<List<NoteReference>> watchLivingNotes({String? searchText});

  /// La madurez de un elemento, si es una nota. `null` si no lo es, o si
  /// todavía no tiene fila en el espejo.
  Stream<NoteMaturity?> watchNoteMaturity(String itemId);

  /// El tipo de un elemento, si es una nota. `null` si no lo es, o si
  /// todavía no tiene fila en el espejo — mismo contrato que
  /// [watchNoteMaturity].
  Stream<NoteKind?> watchNoteKind(String itemId);

  /// Cambia el tipo de una nota. Sin una máquina de estados completa: el
  /// único llamador hoy es "marcar/desmarcar como mapa" desde su
  /// detalle (ver la decisión sobre F6) — marcar escribe [NoteKind.map],
  /// desmarcar escribe [NoteKind.living] sin intentar restaurar el tipo
  /// anterior.
  Future<Either<Failure, Unit>> setNoteKind({
    required String itemId,
    required NoteKind kind,
  });
}
