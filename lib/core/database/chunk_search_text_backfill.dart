import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/database/search_index.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/util/extracted_text_format.dart';

/// Pone al día lo que se busca de los chunks que ya estaban (F46, paso 5i):
/// `chunks.search_text` con la regla de hoy ([kChunkSearchTextRule]) en todo
/// chunk que no la tiene —los de antes de v52, o los calculados con una regla
/// vieja—, como lo guarda `chunkAndPersistSource` al fragmentar.
///
/// - **En segundo plano y no en la migración**: leer Markdown es cosa de
///   Dart, y medido sobre la bóveda sintética con sus páginas web como las de
///   Wikipedia cuesta unos 0,25 ms por chunk —13,6 s con 3.000 elementos, unos
///   45 s con 10.000 en la PC y varias veces más en un teléfono—: demasiado
///   para tener la bóveda cerrada al actualizar la app. Como el relleno del
///   Índice (v51), la migración solo agrega las columnas y esto corre
///   después. Mientras tanto la búsqueda anda como antes: un chunk sin
///   `search_text` se busca por su texto tal cual.
/// - **Por tandas**, de [chunksPerBatch] por transacción, con la lectura del
///   Markdown en otro isolate (`compute`) y el turno a la interfaz entre una
///   y otra: ninguna tanda traba un cuadro. Cada chunk que cambia cambia en el
///   índice por su trigger, exacto: lo que se le dice que se borra es lo que
///   tenía indexado.
/// - **Con su punto de retome en la base misma**: falta lo que no tiene la
///   regla de hoy. Si la app se cierra a mitad de camino, la próxima vez
///   sigue; lo hecho no se rehace. Qué fuente es Markdown lo decide la misma
///   regla de siempre, `extractedTextIsMarkdownFor`, en Dart: no se copia a
///   SQL. Un chunk que no es de Markdown solo recibe la versión.
class ChunkSearchTextBackfill {
  ChunkSearchTextBackfill({
    required AppDatabase database,
    this.chunksPerBatch = 200,
  }) : _db = database;

  final AppDatabase _db;

  /// Cuántos chunks se ponen al día por transacción.
  final int chunksPerBatch;

  /// La pasada en curso: dos pedidos a la vez comparten la misma.
  Future<int>? _running;

  var _stopped = false;

  /// Hace todo lo que falta y devuelve cuántos chunks puso al día. Con
  /// [stop] se corta entre una tanda y la siguiente, y lo hecho queda hecho.
  Future<int> run() => _running ??= _run().whenComplete(() => _running = null);

  /// Corta la pasada en curso al terminar su tanda.
  void stop() => _stopped = true;

  Future<int> _run() async {
    final kinds = SourceKind.values.asNameMap();
    final rule = Variable.withInt(kChunkSearchTextRule);
    var done = 0;
    var after = 0;
    while (!_stopped) {
      // Primero de quién es cada chunk, sin su texto: el de una transcripción
      // o un PDF no hace falta traerlo.
      final rows = await _db
          .customSelect(
            'SELECT c.row_key, s.source_type, s.original_blob_path '
            'FROM chunks c JOIN source s ON s.item_id = c.item_id '
            'WHERE c.row_key > ? AND (c.search_text_rule IS NULL '
            'OR c.search_text_rule <> ?) ORDER BY c.row_key LIMIT ?',
            variables: [
              Variable.withInt(after),
              rule,
              Variable.withInt(chunksPerBatch),
            ],
          )
          .get();
      if (rows.isEmpty) break;
      after = rows.last.read<int>('row_key');
      final markdown = <int>[];
      final plain = <int>[];
      for (final row in rows) {
        final kind = kinds[row.read<String>('source_type')];
        final isMarkdown =
            kind != null &&
            extractedTextIsMarkdownFor(
              kind,
              row.readNullable<String>('original_blob_path'),
            );
        (isMarkdown ? markdown : plain).add(row.read<int>('row_key'));
      }

      final texts = markdown.isEmpty
          ? const <QueryRow>[]
          : await _db
                .customSelect(
                  'SELECT row_key, content, search_text FROM chunks '
                  'WHERE row_key IN (${_placeholders(markdown.length)})',
                  variables: [
                    for (final key in markdown) Variable.withInt(key),
                  ],
                )
                .get();
      // Leer Markdown cuesta: fuera del hilo de la interfaz, para que una
      // tanda no trabe ningún cuadro (en la web, `compute` corre en el mismo).
      final readables = texts.isEmpty
          ? const <String?>[]
          : await compute(_readAll, [
              for (final row in texts) row.read<String>('content'),
            ]);

      await _db.transaction(() async {
        for (final (i, row) in texts.indexed) {
          final readable = readables[i];
          // Lo que se busca cambia solo si cambia: escribir `search_text`
          // igual que estaba reindexaría el chunk por su trigger.
          final same = readable == row.readNullable<String>('search_text');
          await _db.customUpdate(
            same
                ? 'UPDATE chunks SET search_text_rule = ?2 WHERE row_key = ?1'
                : 'UPDATE chunks SET search_text = ?3, search_text_rule = ?2 '
                      'WHERE row_key = ?1',
            variables: [
              Variable.withInt(row.read<int>('row_key')),
              rule,
              if (!same) Variable(readable),
            ],
            updates: {_db.chunks},
          );
        }
        // Lo que no es Markdown se busca tal cual: solo recibe la versión, y
        // pierde lo que se le hubiera calculado como Markdown —un archivo que
        // dejó de serlo—, sin tocar el índice de los demás.
        if (plain.isNotEmpty) {
          final keys = [for (final key in plain) Variable.withInt(key)];
          await _db.customUpdate(
            'UPDATE chunks SET search_text = NULL '
            'WHERE search_text IS NOT NULL '
            'AND row_key IN (${_placeholders(plain.length)})',
            variables: keys,
            updates: {_db.chunks},
          );
          await _db.customUpdate(
            'UPDATE chunks SET search_text_rule = ? '
            'WHERE row_key IN (${_placeholders(plain.length)})',
            variables: [rule, ...keys],
            updates: {_db.chunks},
          );
        }
      });
      done += rows.length;
      // El turno a la interfaz entre una tanda y la siguiente.
      await Future<void>.delayed(Duration.zero);
    }
    return done;
  }

  static String _placeholders(int count) => List.filled(count, '?').join(', ');
}

/// Lo que se busca de cada uno de [contents], textos en Markdown: ver
/// `chunkSearchSource`. De nivel superior para poder correr en otro isolate.
List<String?> _readAll(List<String> contents) => [
  for (final content in contents) chunkSearchSource(content, markdown: true),
];

/// El relleno de lo que se busca de los chunks: se arranca una vez, al abrirse
/// la bóveda (`App`), y se corta si la base se va.
final chunkSearchTextBackfillProvider = Provider<ChunkSearchTextBackfill>((
  ref,
) {
  final backfill = ChunkSearchTextBackfill(
    database: ref.watch(appDatabaseProvider),
  );
  ref.onDispose(backfill.stop);
  return backfill;
});
