import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El censo de escrituras (F11): ningún archivo de `lib` escribe `item`,
/// `note` ni `source` salvo `KnowledgeEntryWriter`. Desde F15, tampoco
/// `source_reference` ni `source_contributor`: los datos bibliográficos y las
/// personas de una obra son UN campo de linaje, y solo dicen la verdad si los
/// escribe quien lo versiona.
///
/// `rev`, `deviceId` y `field_version` solo dicen la verdad si TODA
/// modificación pasa por el mismo lugar: una sola escritura por fuera y la
/// versión de ese campo miente —una fusión creería que nadie lo cambió—. Antes
/// de F11 había cinco lugares que escribían estas filas por su cuenta; este
/// test es lo que impide que vuelvan a ser cinco.
///
/// Es una comprobación de texto, no de tipos: busca las tres formas en que se
/// escribe con drift —una escritura sobre la tabla, una companion de sus
/// filas y SQL crudo—. No detecta una escritura que alguien disfrace a
/// propósito (un alias de la tabla); sí la que se hace sin pensar, que es la
/// que ocurre.
void main() {
  /// Los archivos que escriben estas tablas sin ser el escritor, con el motivo.
  /// Un archivo que ya no escribe nada tiene que salir de la lista: el propio
  /// test lo exige, para que la lista no se vuelva un permiso general.
  const allowed = <String, String>{
    'lib/core/database/knowledge_entry_writer.dart':
        'es EL escritor: todo lo demás pasa por él',
    'lib/core/database/knowledge_source_chunking.dart':
        'source.content_hash: huella del texto de la forma principal, la '
        'rehace el chunking; no es una modificación del usuario',
    'lib/features/duplicates/data/usecases/'
            'generate_duplicate_suggestions_usecase.dart':
        'dedup_hash y simhash: huellas derivadas del texto, se recalculan '
        'cuando hace falta; no son una modificación del usuario',
    'lib/core/database/migrations/mirror_unmirrored_items.dart':
        'migración de F3: espejaba lo que no tenía fila en el modelo nuevo, '
        'con el dispositivo del espejo (todavía no había identidad)',
    'lib/core/database/migrations/backfill_chunks_v16.dart':
        'migración v16: content_hash de las fuentes que ya tenían texto',
    'lib/features/vault/data/merge/entry_merge_applier.dart':
        'la fusión de bóvedas aplica versiones AJENAS que ya traen su linaje: '
        'copia las filas y su field_version tal como vienen; pasarlas por el '
        'escritor les pondría el dispositivo de acá y perdería de qué partían',
  };

  test('el detector ve las tres formas de escribir', () {
    expect(
      writesOfKnowledgeRows('await _db.update(_db.knowledgeEntries).write(x);'),
      isNotEmpty,
    );
    expect(
      writesOfKnowledgeRows('''
        await _db
            .into(_db.knowledgeSources)
            .insert(x);'''),
      isNotEmpty,
    );
    expect(
      writesOfKnowledgeRows('''
        await (db.delete(
          db.knowledgeNotes,
        )..where((n) => n.itemId.equals(id))).go();'''),
      isNotEmpty,
    );
    expect(
      writesOfKnowledgeRows('batch.insertAll(db.knowledgeEntries, rows);'),
      isNotEmpty,
    );
    expect(
      writesOfKnowledgeRows('const c = KnowledgeNotesCompanion(noteKind: v);'),
      isNotEmpty,
    );
    expect(
      writesOfKnowledgeRows("await db.customStatement('UPDATE item SET x=1');"),
      isNotEmpty,
    );
    expect(
      writesOfKnowledgeRows(
        "await db.customStatement('DELETE FROM source WHERE 1');",
      ),
      isNotEmpty,
    );
    expect(
      writesOfKnowledgeRows(
        "await db.customStatement('INSERT OR IGNORE INTO note VALUES (1)');",
      ),
      isNotEmpty,
    );
    // Las referencias bibliográficas y sus personas (F15), en sus tres formas.
    expect(
      writesOfKnowledgeRows(
        'await _db.into(_db.sourceReferences).insertOnConflictUpdate(x);',
      ),
      isNotEmpty,
    );
    expect(
      writesOfKnowledgeRows(
        'await (_db.delete(_db.sourceContributors)..where(w)).go();',
      ),
      isNotEmpty,
    );
    expect(
      writesOfKnowledgeRows('const c = SourceContributorsCompanion(role: v);'),
      isNotEmpty,
    );
    for (final sql in [
      'INSERT INTO source_reference (item_id) VALUES (1)',
      'UPDATE source_contributor SET position = 2',
      'DELETE FROM main.source_contributor WHERE 1',
      'INSERT OR REPLACE INTO main.source_reference (a) VALUES (1)',
    ]) {
      expect(
        writesOfKnowledgeRows("await db.customStatement('$sql');"),
        isNotEmpty,
        reason: sql,
      );
    }
    // También la que nombra la base: la fusión escribe `main.item` con otra
    // adjuntada, y un detector que solo mirara `item` no la vería.
    for (final sql in [
      'UPDATE main.item SET x = 1',
      'INSERT INTO main.note (a) VALUES (1)',
      'INSERT OR REPLACE INTO main.source (a) VALUES (1)',
      'DELETE FROM main.item WHERE 1',
    ]) {
      expect(
        writesOfKnowledgeRows("await db.customStatement('$sql');"),
        isNotEmpty,
        reason: sql,
      );
    }
  });

  test('y no confunde una lectura, un comentario ni otra tabla', () {
    expect(
      writesOfKnowledgeRows('''
        final rows = await _db.select(_db.knowledgeEntries).get();
        final joined = _db.select(_db.knowledgeEntries).join([
          innerJoin(_db.knowledgeNotes, cond),
        ]);
        final refs = await _db.select(_db.sourceReferences).get();
        final who = _db.select(_db.sourceContributors).join([j]);
        await db.customSelect('SELECT * FROM source_reference WHERE 1');
        // await _db.update(_db.knowledgeEntries).write(x);
        /// await _db.delete(_db.knowledgeSources).go();
        '''),
      isEmpty,
    );
    expect(
      writesOfKnowledgeRows('''
        await _db.update(_db.flashcards).write(x);
        await _db.into(_db.relations).insert(x);
        await db.customStatement('INSERT INTO item_search(x) VALUES (1)');
        await db.customStatement('UPDATE item_property_values SET a = 1');
        await db.customStatement('INSERT INTO main.field_version (a) VALUES (1)');
        await db.customStatement('UPDATE main.spaces SET name = 1');
        await db.customStatement('UPDATE incoming.item SET a = 1 WHERE 0');
        '''),
      isEmpty,
    );
  });

  test('solo el escritor y los archivos con motivo escriben item, note y '
      'source', () {
    final files = _dartFilesUnder('lib');
    // El recorrido mira algo: sin esto, un cambio de ruta lo dejaría verde
    // sin revisar nada.
    expect(files.length, greaterThan(200));

    final writers = <String>{
      for (final file in files)
        if (writesOfKnowledgeRows(file.readAsStringSync()).isNotEmpty)
          _relative(file),
    };

    expect(
      writers.difference(allowed.keys.toSet()),
      isEmpty,
      reason:
          'Estos archivos escriben item, note, source, source_reference o '
          'source_contributor sin pasar por KnowledgeEntryWriter: cada '
          'modificación tiene que quedar en rev, deviceId y field_version.',
    );
    expect(
      allowed.keys.toSet().difference(writers),
      isEmpty,
      reason:
          'Estos archivos están en la lista de permitidos pero ya no '
          'escriben esas tablas: quitarlos de la lista.',
    );
  });
}

/// Las escrituras sobre `item`, `note` o `source` que hay en [source]: cada
/// una es el texto que la delata.
List<String> writesOfKnowledgeRows(String source) {
  final code = _withoutComments(source);
  return [
    for (final match in _tableWrite.allMatches(code)) match.group(0)!,
    for (final match in _companion.allMatches(code)) match.group(0)!,
    for (final match in _rawSql.allMatches(code)) match.group(0)!,
  ];
}

/// `update(_db.knowledgeEntries`, `into(\n_db.knowledgeSources`,
/// `insertAll(db.knowledgeNotes`... Los espacios en blanco —también los saltos
/// de línea que deja el formateador— no importan.
final _tableWrite = RegExp(
  r'\b(?:update|into|delete|insertAll|insertAllOnConflictUpdate|replaceAll|'
  r'updateAll|deleteWhere|insert|replace)\s*\(\s*(?:[\w$!?]+\s*\.\s*)*'
  '(?:knowledgeEntries|knowledgeNotes|knowledgeSources|sourceReferences|'
  r'sourceContributors)\b',
);

/// Sin una companion no se escribe una fila tipada.
final _companion = RegExp(
  r'\b(?:KnowledgeEntries|KnowledgeNotes|KnowledgeSources|SourceReferences|'
  r'SourceContributors)Companion\b',
);

/// SQL crudo que modifica `item`, `note`, `source`, `source_reference` o
/// `source_contributor` —no `item_search`, ni `item_property_values`—.
final _rawSql = RegExp(
  r'(?:\bUPDATE|\bINSERT(?:\s+OR\s+\w+)?\s+INTO|\bDELETE\s+FROM|'
  r'\bREPLACE\s+INTO)\s+"?(?:main\.)?'
  r'(?:item|note|source_reference|source_contributor|source)"?(?![\w])',
  caseSensitive: false,
);

/// Sin los comentarios: una escritura citada en la documentación no cuenta.
String _withoutComments(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'(?:^|\s)//[^\n]*'), '');

List<File> _dartFilesUnder(String directory) => [
  for (final entity in Directory(directory).listSync(recursive: true))
    if (entity is File &&
        entity.path.endsWith('.dart') &&
        !entity.path.endsWith('.g.dart') &&
        !entity.path.endsWith('.freezed.dart'))
      entity,
];

/// La ruta relativa a la raíz del proyecto, con `/` aunque sea Windows.
String _relative(File file) => file.path.replaceAll(r'\', '/');
