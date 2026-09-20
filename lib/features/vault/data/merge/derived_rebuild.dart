import 'package:drift/drift.dart' show Variable;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/inline_link_sync.dart';
import 'package:sinapsis/core/database/knowledge_source_chunking.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/vault/data/merge/merge_work.dart';

/// Lo que rehízo [DerivedRebuild].
class DerivedResult {
  const DerivedResult({
    this.sourcesChunked = 0,
    this.sourcesPending = 0,
    this.notesLinked = 0,
    this.flashcardsRelinked = 0,
  });

  /// Fuentes cuyos chunks se hicieron o se rehicieron.
  final int sourcesChunked;

  /// Fuentes que no se pudieron fragmentar: el texto está, íntegro, y el
  /// chunker lo dejó dicho en `MigrationIssues`. Quedan sin chunks hasta que
  /// algo los pida de nuevo.
  final int sourcesPending;

  /// Notas cuyos enlaces `[[ ]]` se registraron.
  final int notesLinked;

  /// Tarjetas a las que se les volvió a encontrar su fragmento.
  final int flashcardsRelinked;
}

/// Rehace lo DERIVADO de lo que la fusión trajo o cambió (F11): los chunks de
/// las fuentes y los enlaces en línea de las notas.
///
/// Los derivados no viajan en la copia: un chunk se calcula del texto, y sus
/// identificadores no son estables —cambiar el texto los rehace—. Se copia lo
/// que el usuario escribió y se vuelve a calcular lo que se calcula; así lo que
/// queda es coherente con el texto de ESTA bóveda, no con el de la otra. Es lo
/// mismo que hace guardar un elemento (`LibraryRepositoryImpl.save`), con las
/// mismas funciones.
///
/// Solo toca los elementos anotados en [MergeWork.touchedItems]: los nuevos y
/// los que recibieron un texto. El resto no se recalcula ni se reescribe.
///
/// Los embeddings no se recalculan acá —necesitan un modelo—: el reemplazo de
/// los chunks los descarta, y los rehace el proceso de siempre.
class DerivedRebuild {
  DerivedRebuild({
    required AppDatabase database,
    required IdGenerator ids,
    Clock clock = DateTime.now,
  }) : _db = database,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final IdGenerator _ids;
  final Clock _clock;

  Future<DerivedResult> apply() async {
    final touched = await _db.customSelect('''
      SELECT t.id AS id, i.kind AS kind, i.title AS title
        FROM ${MergeWork.touchedItems} t
        JOIN main.item i ON i.id = t.id
       ORDER BY t.id''').get();

    var chunked = 0;
    var pending = 0;
    var linked = 0;
    for (final row in touched) {
      final itemId = row.read<String>('id');
      if (row.read<String>('kind') == 'note') {
        if (await _linkNote(itemId, row.read<String>('title'))) linked++;
        continue;
      }
      final outcome = await chunkAndPersistSource(
        _db,
        itemId: itemId,
        ids: _ids,
        reportedBy: 'f11_merge',
      );
      switch (outcome) {
        case SourceChunkingOutcome.populated:
        case SourceChunkingOutcome.rebuilt:
          chunked++;
        case SourceChunkingOutcome.failed:
          pending++;
        case SourceChunkingOutcome.alreadyDone:
        case SourceChunkingOutcome.noTextYet:
          break;
      }
    }

    return DerivedResult(
      sourcesChunked: chunked,
      sourcesPending: pending,
      notesLinked: linked,
      flashcardsRelinked: await _relinkFlashcards(),
    );
  }

  /// Registra los `[[ ]]` de la nota, como al guardarla. Devuelve si tenía
  /// alguna forma de bloques que leer.
  Future<bool> _linkNote(String itemId, String title) async {
    final rows = await _db
        .customSelect(
          '''
      SELECT content FROM main.renditions
       WHERE item_id = ? AND kind = 'blocks' AND content IS NOT NULL
       ORDER BY id''',
          variables: [Variable<String>(itemId)],
        )
        .get();

    final blocks = <ContentBlock>[];
    for (final row in rows) {
      final decoded = tryDecodeContentBlocks(row.read<String>('content'));
      // Bloques que no se pueden leer: los enlaces registrados se dejan como
      // estaban, igual que al guardar. No se borran a ciegas.
      if (decoded == null) return false;
      blocks.addAll(decoded);
    }
    if (rows.isEmpty) return false;

    await syncInlineLinks(
      _db,
      itemId: itemId,
      blocks: blocks,
      ids: _ids,
      clock: _clock,
    );
    // Los enlaces rotos de otras notas que apuntaban a este título.
    await resolveBrokenInlineLinks(
      _db,
      itemId: itemId,
      title: title,
      ids: _ids,
      clock: _clock,
    );
    return true;
  }

  /// A las tarjetas que entraron sin fragmento —los identificadores de los
  /// chunks no viajan— se les vuelve a encontrar el suyo por el rango de
  /// caracteres, como al crearlas: el primero que contiene el comienzo.
  Future<int> _relinkFlashcards() => _db.customUpdate(
    '''
    UPDATE main.flashcards SET source_chunk_id = (
      SELECT c.id FROM main.chunks c
       WHERE c.item_id = flashcards.item_id
         AND c.char_start <= flashcards.source_char_start
         AND c.char_end > flashcards.source_char_start
       ORDER BY c.seq LIMIT 1)
     WHERE source_chunk_id IS NULL
       AND source_char_start IS NOT NULL
       AND item_id IN (SELECT id FROM ${MergeWork.touchedItems})''',
    updates: {_db.flashcards},
  );
}
