import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/chunk_invariant_verifier.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';

import '../support/test_vault.dart';
import 'synthetic_vault.dart' show VaultProfile;

/// Dónde y cómo corre la fusión a escala: de dónde sale la bóveda sintética,
/// adónde va lo que se imprime y qué techos se exigen. Es lo que separa la
/// medición —la misma en escritorio y en un teléfono— de su entorno.
class MergeBenchmarkEnvironment {
  const MergeBenchmarkEnvironment({
    required this.vaultFile,
    required this.log,
    required this.save,
    this.description = 'escritorio, sin describir',
    this.firstMergeCeiling = const Duration(minutes: 5),
    this.repeatMergeCeiling = const Duration(minutes: 1),
    this.importCeiling = const Duration(minutes: 20),
  });

  /// La base de la bóveda sintética de 10.000 elementos, ya armada y cerrada, y
  /// su perfil. La medición trabaja sobre COPIAS: nunca la modifica.
  final Future<({File file, VaultProfile profile})> Function() vaultFile;

  final void Function(String message) log;

  /// Guarda un informe con este nombre, si el entorno tiene dónde.
  final void Function(String name, String content) save;

  /// Dónde corrió, para el encabezado del informe.
  final String description;

  /// Techos de tiempo. No son la meta: son lo que avisa de una regresión de
  /// órdenes de magnitud —un recorrido completo por elemento, por ejemplo—. En
  /// un teléfono se ensanchan hasta tener cifras de uno; ver
  /// `docs/benchmarks/`.
  final Duration firstMergeCeiling;
  final Duration repeatMergeCeiling;
  final Duration importCeiling;
}

/// La fusión a escala de F11: la bóveda de 10.000 elementos y ~300.000 chunks,
/// fusionada con una variante suya que otro dispositivo modificó.
///
/// Se corre a propósito, igual que `vault_benchmark_test.dart`, y no con toda
/// la suite: copia dos veces una base de ~700 MB y la fusiona. En escritorio:
///
///     flutter test test/benchmark/vault_merge_benchmark_test.dart \
///       --dart-define=BENCH=true --timeout none
///
/// y en un teléfono, `tool/bench_android.ps1 -Target
/// vault_merge_benchmark_test`.
///
/// Lo que mide, con dos dispositivos que parten de la misma bóveda:
///
/// - `pc` edita cien títulos, cinco de los que `tel` manda a la papelera, el
///   texto de cinco fuentes y suma cien fuentes propias.
/// - `tel` edita quinientos títulos —cincuenta en común con `pc`—, manda
///   treinta elementos a la papelera, agrega un párrafo al texto de veinte
///   fuentes y suma doscientas fuentes, cincuenta notas, trescientos vínculos
///   y cien tarjetas.
///
/// Y comprueba, además del tiempo, que la fusión no perdió nada: ningún texto
/// de fuente de `pc` cambió, el de `tel` entró entero como otra forma, cada
/// conflicto quedó guardado y los chunks siguen reconstruyendo el texto exacto.
const _pcTitles = 100;
const _telTitles = 500;
const _telTitlesFrom = 50;
const _trashFrom = 600;
const _trashed = 30;
const _pcEditsOfTrashed = 5;
const _editedSourcesFrom = 100;
const _telEditedSources = 20;
const _pcEditedSources = 5;
const _telNewSources = 200;
const _telNewNotes = 50;
const _pcNewSources = 100;
const _telRelations = 300;
const _telCards = 100;

void registerVaultMergeBenchmark(MergeBenchmarkEnvironment env) {
  test('una variante de la bóveda de 10.000 elementos, y una copia en una '
      'bóveda vacía', () async {
    final report = StringBuffer('# Fusión a escala (F11)\n\n')
      ..writeln('Equipo: ${env.description}')
      ..writeln();
    void say(String line) {
      env.log(line);
      report.writeln(line);
    }

    final (file: source, :profile) = await env.vaultFile();

    final work = await Directory.systemTemp.createTemp('sinapsis_merge_bench_');
    addTearDown(() async {
      try {
        await work.delete(recursive: true);
        // En Windows un archivo recién cerrado puede tardar en soltarse.
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {}
    });

    final aFile = File(p.join(work.path, 'pc.sqlite'));
    final bFile = File(p.join(work.path, 'tel.sqlite'));
    final copyWatch = Stopwatch()..start();
    await source.copy(aFile.path);
    await source.copy(bFile.path);
    say(
      '- dos copias de la bóveda de ${profile.items} elementos '
      '(${source.lengthSync() ~/ (1024 * 1024)} MB cada una): '
      '${copyWatch.elapsedMilliseconds} ms',
    );

    final pc = await TestVault.onFile(aFile, deviceId: 'pc');
    addTearDown(pc.dispose);
    final tel = await TestVault.onFile(bFile, deviceId: 'tel');

    final itemIds = await _ids(pc.db, 'SELECT id FROM item ORDER BY id');
    final sourceIds = await _ids(
      pc.db,
      'SELECT item_id AS id FROM source ORDER BY item_id',
    );
    expect(itemIds, hasLength(profile.items));

    // ── tel edita ─────────────────────────────────────────────────────
    final telWatch = Stopwatch()..start();
    tel.at(10);
    for (var i = _telTitlesFrom; i < _telTitlesFrom + _telTitles; i++) {
      expect(
        await tel.writer.setFieldFromText(
          itemIds[i],
          EntryField.title,
          'Editado en tel $i',
        ),
        isTrue,
      );
    }
    (await tel.library.deleteMany([
      for (var i = 0; i < _trashed; i++) itemIds[_trashFrom + i],
    ])).fold((f) => fail('$f'), (_) {});
    final telEdited = <String, String>{};
    for (var k = 0; k < _telEditedSources; k++) {
      final id = sourceIds[_editedSourcesFrom + k];
      telEdited[id] = await _appendToText(tel, id, 'Agregado en tel.');
    }
    for (var i = 0; i < _telNewSources; i++) {
      await tel.saveSource('tel-src-$i', text: _longText('tel', i));
    }
    for (var i = 0; i < _telNewNotes; i++) {
      await tel.saveNote('tel-note-$i', text: 'Una idea de tel, la $i.');
    }
    for (var i = 0; i < _telRelations; i++) {
      await tel.addRelation(
        'tel-rel-$i',
        i.isEven ? 'tel-src-${i % _telNewSources}' : 'tel-note-${i % 50}',
        itemIds[i * 11],
      );
    }
    for (var i = 0; i < _telCards; i++) {
      await tel.addFlashcard('tel-card-$i', itemIds[2000 + i]);
    }
    say('- lo que edita tel: ${telWatch.elapsedMilliseconds} ms');
    final telDigest = await _textDigest(tel.db);
    final telItems = await tel.count('item');
    final telCounts = await tel.counts();
    await tel.db.close();

    // ── pc edita ──────────────────────────────────────────────────────
    final pcWatch = Stopwatch()..start();
    pc.at(20);
    for (var i = 0; i < _pcTitles; i++) {
      await pc.writer.setFieldFromText(
        itemIds[i],
        EntryField.title,
        'Editado en pc $i',
      );
    }
    for (var i = 0; i < _pcEditsOfTrashed; i++) {
      await pc.writer.setFieldFromText(
        itemIds[_trashFrom + i],
        EntryField.title,
        'Editado en pc, borrado en tel $i',
      );
    }
    for (var k = 0; k < _pcEditedSources; k++) {
      await _appendToText(
        pc,
        sourceIds[_editedSourcesFrom + k],
        'Agregado en pc.',
      );
    }
    for (var i = 0; i < _pcNewSources; i++) {
      await pc.saveSource('pc-src-$i', text: _longText('pc', i));
    }
    say('- lo que edita pc: ${pcWatch.elapsedMilliseconds} ms');

    final pcItemsBefore = await pc.count('item');
    final pcDigestBefore = await _textDigest(pc.db);
    expect(pcItemsBefore, profile.items + _pcNewSources);

    // ── la fusión ─────────────────────────────────────────────────────
    pc.at(30);
    final mergeWatch = Stopwatch()..start();
    final first = await pc.mergeDatabaseFile(bFile);
    final firstMs = mergeWatch.elapsedMilliseconds;
    say('- **fusionar la copia de tel en pc: $firstMs ms** ($first)');

    const keptAlive = _pcEditsOfTrashed;
    const overlapping = _pcTitles - _telTitlesFrom;
    expect(first.itemsAdded, _telNewSources + _telNewNotes);
    expect(first.sourcesChunked, _telNewSources);
    expect(first.relationsAdded, _telRelations);
    expect(first.flashcardsAdded, _telCards);
    // Cincuenta títulos editados a la vez, cinco borrados contra una
    // edición y veinte textos de fuente que entran como otra forma.
    expect(
      first.conflictsRecorded,
      overlapping + keptAlive + _telEditedSources,
    );
    expect(first.filesCopied, 0);

    expect(
      await pc.count('item'),
      pcItemsBefore + _telNewSources + _telNewNotes,
    );
    final trashed = await pc.count('item WHERE deleted_at IS NOT NULL');
    expect(trashed, _trashed - keptAlive);

    // El texto de las fuentes de pc no cambió, ni uno.
    expect(
      await _textDigest(pc.db),
      pcDigestBefore,
      reason: 'ningún texto que pc ya tenía se reescribe',
    );
    // El de tel entró entero, como otra forma no principal.
    for (final MapEntry(:key, :value) in telEdited.entries) {
      final extra = await pc.db
          .customSelect(
            'SELECT content FROM renditions '
            'WHERE item_id = ? AND is_primary = 0',
            variables: [Variable<String>(key)],
          )
          .get();
      expect(extra.map((r) => r.read<String>('content')), [value]);
    }
    expect(
      await pc.count('merge_conflict WHERE resolved_at IS NULL'),
      first.conflictsRecorded,
    );

    final invariantWatch = Stopwatch()..start();
    final pcReport = await verifyChunkInvariant(pc.db);
    say(
      '- `verifyChunkInvariant` de pc, entera: ${pcReport.summary()} '
      '(${invariantWatch.elapsedMilliseconds} ms)',
    );
    expect(pcReport.holds, isTrue, reason: pcReport.summary());
    expect(await pc.db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);

    // ── otra vez lo mismo: no cambia nada ────────────────────────────
    pc.at(40);
    final againWatch = Stopwatch()..start();
    final again = await pc.mergeDatabaseFile(bFile);
    final againMs = againWatch.elapsedMilliseconds;
    say('- fusionar lo mismo otra vez: $againMs ms ($again)');
    expect(
      again.changedNothing,
      isTrue,
      reason: 'fusionar dos veces la misma copia no cambia nada: $again',
    );
    expect(await pc.count('item'), pcItemsBefore + 250);

    // ── la copia de tel en una bóveda vacía ──────────────────────────
    final eFile = File(p.join(work.path, 'nueva.sqlite'));
    final empty = await TestVault.onFile(eFile, deviceId: 'nueva');
    addTearDown(empty.dispose);
    empty.at(50);
    final importWatch = Stopwatch()..start();
    final imported = await empty.mergeDatabaseFile(bFile);
    final importMs = importWatch.elapsedMilliseconds;
    say(
      '- **la copia de tel en una bóveda vacía: $importMs ms** '
      '($imported)',
    );
    expect(imported.itemsAdded, telItems);
    expect(imported.conflictsRecorded, 0);
    expect(
      await _textDigest(empty.db),
      telDigest,
      reason: 'el texto de cada fuente llegó idéntico',
    );
    final emptyCounts = await empty.counts();
    for (final table in [
      'item',
      'source',
      'note',
      'renditions',
      'highlights',
      'flashcards',
      'item_property_values',
    ]) {
      expect(emptyCounts[table], telCounts[table], reason: table);
    }
    // Los vínculos entraron todos, y de más: rehacer los enlaces `[[ ]]` de
    // las notas crea el vínculo «relacionado» de cada uno que resuelve, que
    // es lo que hace guardar una nota y lo que el generador sintético no
    // escribe junto a sus enlaces.
    expect(
      emptyCounts['relations'],
      greaterThanOrEqualTo(telCounts['relations']!),
      reason: 'relations',
    );
    say(
      '- vínculos: ${telCounts['relations']} en la copia, '
      '${emptyCounts['relations']} en la bóveda vacía '
      '(los `[[ ]]` de las notas, ya resueltos)',
    );

    final emptyInvariantWatch = Stopwatch()..start();
    final emptyReport = await verifyChunkInvariant(empty.db);
    say(
      '- `verifyChunkInvariant` de la bóveda vacía, entera: '
      '${emptyReport.summary()} '
      '(${emptyInvariantWatch.elapsedMilliseconds} ms)',
    );
    expect(emptyReport.holds, isTrue, reason: emptyReport.summary());
    expect(
      await empty.db.customSelect('PRAGMA foreign_key_check').get(),
      isEmpty,
    );

    env.save('latest_merge_report.md', report.toString());

    // Techos con mucho margen: no son la meta, son lo que avisaría de una
    // regresión de órdenes de magnitud (un recorrido completo por
    // elemento, por ejemplo).
    expect(firstMs, lessThan(env.firstMergeCeiling.inMilliseconds));
    expect(againMs, lessThan(env.repeatMergeCeiling.inMilliseconds));
    expect(importMs, lessThan(env.importCeiling.inMilliseconds));
  }, timeout: const Timeout(Duration(minutes: 60)));
}

Future<List<String>> _ids(AppDatabase db, String sql) async => [
  for (final row in await db.customSelect(sql).get()) row.read<String>('id'),
];

/// Un texto de treinta párrafos, para las fuentes nuevas: unos 6 KB, que dan
/// una decena de chunks.
String _longText(String device, int n) => List.generate(
  30,
  (k) =>
      'Párrafo $k de la fuente $n de $device. Habla de la república romana y '
      'de sus magistrados, del senado y de las guerras de conquista.',
).join('\n\n');

/// Agrega un párrafo al texto principal de la fuente [id] guardándola como lo
/// haría la app, y devuelve el texto que quedó.
Future<String> _appendToText(TestVault vault, String id, String more) async {
  final item = (await vault.library.findById(
    id,
  )).fold((f) => fail('$f'), (found) => found!);
  final primary = item.renditions.whereType<TextRendition>().firstWhere(
    (r) => r.isPrimary,
  );
  final text = '${primary.content}\n\n$more';
  (await vault.library.save(
    item.copyWith(
      updatedAt: vault.now,
      renditions: [
        for (final r in item.renditions)
          if (r.id == primary.id) primary.copyWith(content: text) else r,
      ],
    ),
  )).fold((f) => fail('$f'), (_) {});
  return text;
}

/// Un solo hash de los textos de las formas que trae la bóveda sintética —los
/// ids que empiezan con ceros—: se lee de a páginas porque juntos pesan cientos
/// de megas.
Future<String> _textDigest(AppDatabase db) async {
  var digest = sha256.convert(const <int>[]);
  var after = '';
  while (true) {
    final rows = await db
        .customSelect(
          'SELECT id, content FROM renditions '
          "WHERE id > ? AND id LIKE '00000000-%' ORDER BY id LIMIT 400",
          variables: [Variable<String>(after)],
        )
        .get();
    if (rows.isEmpty) break;
    for (final row in rows) {
      digest = sha256.convert([
        ...digest.bytes,
        ...utf8.encode(row.read<String>('id')),
        ...sha256
            .convert(utf8.encode(row.read<String?>('content') ?? ''))
            .bytes,
      ]);
    }
    after = rows.last.read<String>('id');
  }
  return digest.toString();
}
