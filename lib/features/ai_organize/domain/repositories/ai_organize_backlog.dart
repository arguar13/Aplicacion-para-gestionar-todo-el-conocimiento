import 'package:flutter/foundation.dart';

/// Lo que la IA tiene pendiente de organizar (F27), deducido de la base y no
/// de una lista en memoria: si la app se cierra a mitad, al volver se sabe
/// qué falta sin haber guardado nada aparte.
///
/// Un elemento está pendiente si está vivo, listo —una fuente procesada, o
/// una nota— y no tiene ninguna pasada terminada ni deshecha. Una deshecha
/// cuenta como hecha: la persona no quiere lo que la IA hizo con él, y la IA
/// no lo vuelve a organizar sola. Una pasada que quedó a medias —la app se
/// cerró— no cuenta, hasta un tope de intentos: algo que hace caer la app
/// cada vez no se retoma para siempre.
///
/// Una nota, además, tiene que llevar un rato sin cambios: la IA no la
/// organiza mientras se escribe.
abstract interface class AiOrganizeBacklog {
  /// El próximo elemento nuevo —creado desde [since]— por organizar, del más
  /// viejo al más nuevo: en el orden en que llegaron. Las notas, solo si no
  /// cambiaron desde [notesQuietBefore]. Sin los de [skip].
  Future<String?> nextFresh({
    required DateTime since,
    required DateTime notesQuietBefore,
    Set<String> skip = const {},
  });

  /// El próximo de la biblioteca que ya existía —creado antes de [before]—,
  /// del más nuevo al más viejo: lo reciente es lo que más se consulta.
  Future<String?> nextExisting({
    required DateTime before,
    required DateTime notesQuietBefore,
    Set<String> skip = const {},
  });

  /// Las notas que la IA ya organizó y que cambiaron después, sin cambios
  /// desde [quietBefore], con cuándo cambiaron y la huella del texto que vio
  /// su última pasada. Si cambiaron lo suficiente para volver a organizarlas
  /// lo decide la cola.
  Future<List<EditedNote>> editedNotes({required DateTime quietBefore});

  /// Cuántos faltan: los nuevos —desde [epoch]— y los de la biblioteca que
  /// ya existía.
  Future<AiBacklogCount> count({
    required DateTime epoch,
    required DateTime notesQuietBefore,
  });

  /// La última vez que se guardó una nota, cada vez que cambia: lo que le
  /// avisa a la cola que hay una nota por organizar cuando termine de
  /// escribirse.
  Stream<DateTime?> watchLastNoteEdit();
}

/// Una nota que cambió después de que la IA la organizó: cuándo, y la huella
/// del texto que vio la última pasada (`ai_runs.content_simhash`); `null` si
/// esa pasada no la guardó —una de antes de v35—.
typedef EditedNote = ({String itemId, DateTime updatedAt, String? simhashSeen});

/// Cuántos elementos esperan a la IA.
@immutable
class AiBacklogCount {
  const AiBacklogCount({this.fresh = 0, this.existing = 0});

  /// Nuevos: se organizan apenas están listos.
  final int fresh;

  /// De la biblioteca que ya existía: solo con el teléfono cargando.
  final int existing;

  @override
  bool operator ==(Object other) =>
      other is AiBacklogCount &&
      other.fresh == fresh &&
      other.existing == existing;

  @override
  int get hashCode => Object.hash(fresh, existing);
}
