import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/text_notes/data/repositories/text_note_repository_impl.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note_target.dart';
import 'package:sinapsis/features/text_notes/domain/repositories/text_note_repository.dart';
import 'package:sinapsis/features/text_notes/domain/services/text_note_placement.dart';

// Las notas en el texto (F45, mejora 19): lo que usa la interfaz —la segunda
// parte del paso 8, sobre el marco de lectura de F47—.
//
// - **De qué texto**: `textNoteTargetOf(studyText)` lo dice para todo lo que
//   el lector muestra como un `StudyText` —el original de la Biblioteca, la
//   copia de Procesado y el texto procesado, también su resumen y su
//   síntesis—; lo creado usa `TextNoteTarget.creation(id)`.
// - **Los globitos y el subrayado punteado**: [placedTextNotesProvider], con
//   el texto que se pinta. Una nota sin lugar no se pinta: va a la lista.
// - **«Notas (N)»**: N es [textNoteCountProvider]; la lista,
//   [placedTextNotesProvider] —en el orden del texto, con «Sin lugar» al
//   final— o, sin el texto a mano, [textNotesProvider].
// - **Las acciones**, en [textNoteRepositoryProvider]: `create` (con
//   «Nota», sobre lo elegido), `edit` (se guarda sola mientras se escribe:
//   la primera letra crea, lo que sigue edita; en blanco no se guarda —para
//   sacarla, «Borrar»—), `recolor` («Cambiar color»), `delete` y, para el
//   «Deshacer» de su aviso, `restore` con la nota que `delete` devolvió.
//   Ninguna toca el documento.
// - Las notas de los resaltados de antes (F38) llegan mezcladas con las
//   nuevas, con `origin: TextNoteOrigin.highlight`: se muestran igual, y sus
//   acciones van al resaltado.

/// Las notas en el texto, sobre la base.
final textNoteRepositoryProvider = Provider<TextNoteRepository>(
  (ref) => TextNoteRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Las notas de un texto, en el orden del texto según su lugar guardado —las
/// sin lugar, al final—, al día. Para pintarlas sobre el texto que se muestra,
/// [placedTextNotesProvider].
final textNotesProvider = StreamProvider.autoDispose
    .family<List<TextNote>, TextNoteTarget>(
      (ref, target) => ref.watch(textNoteRepositoryProvider).watchNotes(target),
    );

/// Cuántas notas tiene un texto, al día: el N de «Notas (N)», sin traerlas.
final textNoteCountProvider = StreamProvider.autoDispose
    .family<int, TextNoteTarget>(
      (ref, target) => ref.watch(textNoteRepositoryProvider).watchCount(target),
    );

/// Las notas de `target` sobre el texto que se muestra, `content`: cada una
/// en su lugar de ESE texto, o sin lugar si su pedazo ya no está, en el orden
/// del texto (`placeTextNotes`).
typedef TextNotesInText = ({TextNoteTarget target, String content});

/// Ver [TextNotesInText].
final placedTextNotesProvider = Provider.autoDispose
    .family<AsyncValue<List<PlacedTextNote>>, TextNotesInText>(
      (ref, key) => ref
          .watch(textNotesProvider(key.target))
          .whenData((notes) => placeTextNotes(notes, content: key.content)),
    );
