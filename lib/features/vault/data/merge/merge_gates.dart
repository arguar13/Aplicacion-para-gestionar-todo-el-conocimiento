import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/chunk_invariant_verifier.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sinapsis/features/vault/data/merge/merge_work.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_service.dart';

/// Cómo estaba la bóveda antes de fusionar.
class MergeSnapshot {
  const MergeSnapshot({
    required this.items,
    required this.counts,
    required this.brokenReferences,
  });

  /// Cuántos elementos había.
  final int items;

  /// Filas por tabla de lo que el usuario creó.
  final VaultCounts counts;

  /// Referencias que ya estaban rotas, por tabla: no son culpa de la fusión.
  final Map<String, int> brokenReferences;
}

/// Las compuertas de una fusión (F11): lo que tiene que ser verdad después de
/// escribir para que la fusión se confirme; si no, se revierte.
///
/// Hay dos clases, y se complementan:
///
/// - Las **guardas** son disparadores temporales que existen mientras dura la
///   fusión y hacen imposible —no solo detectable— lo que una fusión nunca
///   debe hacer: borrar un elemento o una forma de texto, reescribir el texto o
///   el archivo de una forma de una FUENTE, tocar los chunks de un elemento que
///   la fusión no marcó para reprocesar. Cualquier sentencia que lo intente,
///   venga de donde venga, aborta la transacción en el acto. Cuestan casi nada:
///   miran solo lo que se escribe.
/// - Las **verificaciones** miran el resultado: los elementos de antes siguen y
///   los nuevos entraron; ninguna tabla de lo del usuario tiene menos filas que
///   antes; el texto de lo que se fragmentó de nuevo se reconstruye exacto
///   desde sus chunks; y no hay referencias rotas que antes no había.
///
/// Nada de esto reemplaza a la transacción: es lo que le da algo que revertir.
class MergeGates {
  MergeGates(this._db);

  final AppDatabase _db;

  /// Las tablas de lo que el usuario creó que una fusión no puede achicar. Las
  /// derivadas —los chunks, sus embeddings y los enlaces en línea— quedan
  /// afuera: se rehacen. También las versiones por campo: una versión que la
  /// copia no tiene deja el campo como valor de partida, y eso quita su fila.
  static final _neverShrink = <String>[
    ...VaultCounts.userDataTables.where(
      (t) => !const {'chunks', 'embeddings', 'inline_link'}.contains(t),
    ),
    ...VaultCounts.modelTables,
    ...VaultCounts.durabilityTables.where((t) => t != 'field_version'),
    ...VaultCounts.habitTables,
    // Las pasadas de la IA y lo que «no era» (F27): una fusión solo suma.
    ...VaultCounts.aiTables,
  ];

  /// Las tablas donde una referencia rota puede venir de la fusión.
  static const _referencing = <String>[
    'item',
    'note',
    'source',
    'renditions',
    'highlights',
    'relations',
    'flashcards',
    'review_log',
    'merged_provenances',
    'conversations',
    'chat_messages',
    'property_values',
    'property_aliases',
    'item_property_values',
    'field_version',
    'merge_conflict',
    'chunks',
    'inline_link',
    // Los datos bibliográficos de una fuente y sus personas (F15).
    'source_reference',
    'source_contributor',
    // Las pasadas de la IA y lo que «no era» (F27).
    'ai_runs',
    'ai_rejections',
  ];

  /// Lo que se cuenta de una tabla cuando no es toda: el espejo de las
  /// personas de una obra (`item_property_values` con origen `reference`) es
  /// derivado —lo rehace la fusión con las personas que ganaron— y puede
  /// achicarse cuando la referencia de la copia reemplaza a la de acá. Lo que
  /// el usuario asignó, no.
  ///
  /// `source_reference` y `source_contributor` no están entre las que no pueden
  /// achicarse por lo mismo que las versiones por campo: son el valor de un
  /// campo, y uno que gana puede tener menos personas que el que reemplaza.
  static const _countOnly = {'item_property_values': "origin <> 'reference'"};

  /// Toma cómo está la bóveda antes de escribir nada.
  Future<MergeSnapshot> snapshot() async {
    final counts = await captureVaultCounts(
      _db,
      tables: {..._neverShrink, 'chunks', 'embeddings', 'inline_link'},
      where: _countOnly,
    );
    return MergeSnapshot(
      items: counts.rows['item'] ?? 0,
      counts: counts,
      brokenReferences: await _brokenReferences(),
    );
  }

  /// Instala las guardas. Se sueltan con [removeGuards].
  Future<void> installGuards() async {
    for (final sql in const [
      '''
      CREATE TEMP TRIGGER merge_guard_item_delete
      BEFORE DELETE ON main.item
      BEGIN
        SELECT RAISE(ABORT, 'merge-guard: la fusión no borra elementos');
      END''',
      '''
      CREATE TEMP TRIGGER merge_guard_rendition_delete
      BEFORE DELETE ON main.renditions
      BEGIN
        SELECT RAISE(ABORT, 'merge-guard: la fusión no borra formas de texto');
      END''',
      '''
      CREATE TEMP TRIGGER merge_guard_source_text
      BEFORE UPDATE OF content, relative_path ON main.renditions
      WHEN EXISTS (
        SELECT 1 FROM main.item i WHERE i.id = OLD.item_id AND i.kind = 'source')
      BEGIN
        SELECT RAISE(
          ABORT, 'merge-guard: la fusión no reescribe el texto de una fuente');
      END''',
    ]) {
      await _db.customStatement(sql);
    }
    for (final event in const ['UPDATE', 'DELETE']) {
      await _db.customStatement('''
        CREATE TEMP TRIGGER merge_guard_chunk_${event.toLowerCase()}
        BEFORE $event ON main.chunks
        WHEN OLD.item_id NOT IN (SELECT id FROM ${MergeWork.touchedItems})
        BEGIN
          SELECT RAISE(
            ABORT, 'merge-guard: la fusión no toca los chunks de lo que no cambió');
        END''');
    }
  }

  Future<void> removeGuards() async {
    for (final name in const [
      'merge_guard_item_delete',
      'merge_guard_rendition_delete',
      'merge_guard_source_text',
      'merge_guard_chunk_update',
      'merge_guard_chunk_delete',
    ]) {
      await _db.customStatement('DROP TRIGGER IF EXISTS temp.$name');
    }
  }

  /// Comprueba el resultado. Lanza [VaultMergeGateException] si algo no se
  /// cumple; quien llama deja que la transacción se revierta.
  ///
  /// [itemsAdded] son los elementos que entraron; [rebuilt] los que se
  /// reprocesaron, cuyo texto se comprueba contra sus chunks.
  Future<void> verify({
    required MergeSnapshot before,
    required int itemsAdded,
    required Iterable<String> rebuilt,
  }) async {
    final after = await captureVaultCounts(
      _db,
      tables: {..._neverShrink, 'chunks', 'embeddings', 'inline_link'},
      where: _countOnly,
    );

    final expected = before.items + itemsAdded;
    final items = after.rows['item'] ?? 0;
    if (items != expected) {
      throw VaultMergeGateException(
        'items',
        'había ${before.items} elementos y entraron $itemsAdded: tendría que '
            'haber $expected y hay $items.',
      );
    }

    for (final table in _neverShrink) {
      final was = before.counts.rows[table] ?? 0;
      final now = after.rows[table] ?? 0;
      if (now < was) {
        throw VaultMergeGateException(
          'counts',
          'la tabla $table tenía $was filas y ahora tiene $now: una fusión '
              'solo suma.',
        );
      }
    }

    final report = await verifyChunkInvariant(_db, onlyItemIds: rebuilt);
    // Una fuente que el fragmentador no pudo procesar queda sin chunks —y
    // reportada—: el texto está y se reintenta. Que los chunks que SÍ hay no
    // reconstruyan el texto, en cambio, es exactamente lo que no puede pasar.
    final broken = [
      for (final v in report.violations)
        if (v.problem != ChunkInvariantProblem.missingChunks) v,
    ];
    if (broken.isNotEmpty) {
      throw VaultMergeGateException(
        'text',
        'los chunks no reconstruyen el texto: ${broken.take(3).join('; ')}'
            '${broken.length > 3 ? ' (y ${broken.length - 3} más)' : ''}.',
      );
    }

    final now = await _brokenReferences();
    for (final entry in now.entries) {
      final was = before.brokenReferences[entry.key] ?? 0;
      if (entry.value > was) {
        throw VaultMergeGateException(
          'references',
          'la tabla ${entry.key} tiene ${entry.value - was} referencias rotas '
              'que antes no había.',
        );
      }
    }
  }

  /// Cuántas filas de cada tabla apuntan a algo que no existe.
  Future<Map<String, int>> _brokenReferences() async {
    final broken = <String, int>{};
    for (final table in _referencing) {
      final rows = await _db
          .customSelect('PRAGMA foreign_key_check($table)')
          .get();
      broken[table] = rows.length;
    }
    return broken;
  }
}
