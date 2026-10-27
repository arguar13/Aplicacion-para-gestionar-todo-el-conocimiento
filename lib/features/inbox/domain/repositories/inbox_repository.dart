import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/inbox/domain/entities/inbox_standing.dart';
import 'package:sinapsis/features/inbox/domain/entities/note_reference.dart';
import 'package:sinapsis/features/inbox/domain/entities/pending_source.dart';
import 'package:sinapsis/features/inbox/domain/entities/pending_text.dart';
import 'package:sinapsis/features/inbox/domain/entities/source_extent.dart';

/// El lado del espejo `item`/`source`/`note` (ver la decisión sobre F3 en
/// docs/arquitectura.md) que sirve a la Bandeja de entrada: qué queda por
/// triar, cómo se transiciona un elemento, y qué notas vivas existen para
/// vincular. Primer lector y escritor real de esas tablas desde que
/// existen —F1 solo las pobló, nunca las leyó—.
abstract interface class InboxRepository {
  /// Los ids de las fuentes que esperan triaje —`captured` o `processed`:
  /// desde F41, todo lo nuevo de la Biblioteca apenas se guarda, tenga su
  /// texto o no—, de la que se guardó primero a la última (`createdAt`
  /// ascendente: la que lleva más tiempo esperando va primero).
  ///
  /// El orden es el de llegada y no se mueve solo: ni que llegue el texto ni
  /// editar la fuente la cambian de lugar, así la tarjeta que se está mirando
  /// mientras espera su texto sigue arriba cuando llega.
  ///
  /// Filtra `kind == ItemKind.source` — las notas no se trían, su progreso
  /// se mide con [watchNoteMaturity], no con este flujo.
  Stream<List<String>> watchPendingIds();

  /// Lo mismo que [watchPendingIds], en el mismo orden, con lo justo para
  /// listarlo: la cola entera detrás de «N pendientes» (F28), y si cada una
  /// ya tiene su texto (F41).
  Stream<List<PendingSource>> watchPending();

  /// En qué está el texto de [itemId] (F41): lo que la tarjeta del mazo dice
  /// mientras lo espera, y lo que prende o apaga sus acciones. Se actualiza
  /// solo cuando llega el texto o cambia el procesamiento. `null` si no
  /// existe o no es una fuente. Ver [PendingText].
  Stream<PendingText?> watchPendingText(String itemId);

  /// Dónde está [itemId] respecto de la Bandeja y desde cuándo (F28), o
  /// `null` si no tiene nada que ver con ella —una nota, algo que ya no
  /// existe—. Ver [InboxStanding].
  Stream<InboxStanding?> watchStanding(String itemId);

  /// Cuánto es [itemId]: las páginas de un PDF o lo que dura un audio o un
  /// video, para la línea de datos de la tarjeta (F30, decisión 68). Ver
  /// [SourceExtent]; sin ninguna de las dos, [SourceExtent.none].
  Stream<SourceExtent> watchExtent(String itemId);

  /// Cambia el estado de un elemento. Sin una máquina de estados
  /// completa: los llamadores son las acciones de la Bandeja (`→ discarded`,
  /// `→ triaged`). Volver a la Bandeja es [returnToInbox].
  Future<Either<Failure, Unit>> transitionState({
    required String itemId,
    required ItemState to,
  });

  /// Devuelve la fuente [itemId] a la Bandeja: deshacer una decisión del mazo
  /// y «Volver a la Bandeja» desde el detalle (F28).
  ///
  /// Al estado de espera que le corresponde **ahora**, según su procesamiento
  /// (F41): `processed` si ya terminó, `captured` si todavía se está sacando
  /// el texto, espera su turno o falló —lo mismo con que nace una fuente,
  /// `initialItemStateFor`—. Mientras se procesa, el espejo la pasa solo a
  /// `processed` cuando termina.
  ///
  /// Falla si no existe o no es una fuente.
  Future<Either<Failure, Unit>> returnToInbox(String itemId);

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

  /// Cambia la madurez de una nota —`seed`, `developing`, `mature`—. La
  /// madurez la decide quien escribe: nada la mueve sola, y se puede volver
  /// atrás. Falla si la nota ya no existe.
  Future<Either<Failure, Unit>> setNoteMaturity({
    required String itemId,
    required NoteMaturity maturity,
  });

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
