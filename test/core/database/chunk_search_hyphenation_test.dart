import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/search_index.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

import '../../support/item_rows.dart';

/// El índice de los chunks encuentra las palabras cortadas por guion al
/// final del renglón, aunque el texto guardado las conserve cortadas (F22),
/// contra SQLite real.
void main() {
  late AppDatabase db;
  var counter = 0;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    counter = 0;
    await insertItemRows(
      db,
      id: 'libro',
      title: 'Éxodo',
      kind: SourceKind.document,
    );
  });

  tearDown(() => db.close());

  Future<int> addChunk(String content) async {
    final id = 'chunk-${counter++}';
    await db
        .into(db.chunks)
        .insert(
          ChunksCompanion.insert(
            id: id,
            itemId: 'libro',
            seq: counter,
            content: content,
            charStart: 0,
            charEnd: content.length,
          ),
        );
    return (await (db.select(
      db.chunks,
    )..where((c) => c.id.equals(id))).getSingle()).rowKey;
  }

  Future<int> matches(String userInput) async {
    final rows = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM chunk_search WHERE chunk_search MATCH ?',
          variables: [Variable.withString(buildSearchQuery(userInput))],
        )
        .get();
    return rows.single.data['n']! as int;
  }

  test('una palabra cortada por guion se encuentra entera, y el texto '
      'guardado sigue cortado', () async {
    await addChunk('he eludido las ex-\nplicaciones técnicas');

    expect(await matches('explicaciones'), 1);
    expect(await matches('las explicaciones técnicas'), 1);
    final stored = await db.select(db.chunks).getSingle();
    expect(stored.content, 'he eludido las ex-\nplicaciones técnicas');
  });

  test('un compuesto o un rango al final del renglón se encuentran por sus '
      'partes, también', () async {
    await addChunk('un enfoque teórico-\npráctico entre 1990-\n1995');

    expect(await matches('teórico'), 1);
    expect(await matches('práctico'), 1);
    expect(await matches('1990'), 1);
    expect(await matches('1995'), 1);
  });

  test('el guion suave, el tipográfico y el salto de Windows, igual', () async {
    await addChunk('cono­\ncimiento');
    await addChunk('funda‐\nmento');
    await addChunk('reve-\r\nlación');

    expect(await matches('conocimiento'), 1);
    expect(await matches('fundamento'), 1);
    expect(await matches('revelación'), 1);
  });

  test('cambiar y borrar un chunk con guiones deja el índice exacto', () async {
    final rowKey = await addChunk('las ex-\nplicaciones');

    await (db.update(db.chunks)..where((c) => c.rowKey.equals(rowKey))).write(
      const ChunksCompanion(content: Value('otra re-\nvelación')),
    );
    expect(await matches('explicaciones'), 0);
    expect(await matches('revelación'), 1);

    await (db.delete(db.chunks)..where((c) => c.rowKey.equals(rowKey))).go();
    expect(await matches('revelación'), 0);
    // El índice de contenido externo lo confirma: si el borrado hubiera
    // dicho otro texto que el indexado, esto falla.
    await db.customStatement(
      "INSERT INTO chunk_search (chunk_search) VALUES ('integrity-check')",
    );
  });

  test('reconstruir el índice indexa exactamente lo mismo que los '
      'triggers', () async {
    await addChunk('las ex-\nplicaciones');
    await addChunk('un texto sin cortes');

    await db.customStatement(rebuildChunkSearch);
    await db.customStatement(
      "INSERT INTO chunk_search (chunk_search) VALUES ('integrity-check')",
    );

    expect(await matches('explicaciones'), 1);
    expect(await matches('cortes'), 1);
  });
}
