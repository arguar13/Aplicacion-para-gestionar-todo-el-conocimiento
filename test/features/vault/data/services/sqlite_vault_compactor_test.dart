import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/database/knowledge_source_chunking.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sinapsis/features/vault/data/services/sqlite_compaction_advisor.dart';
import 'package:sinapsis/features/vault/data/services/sqlite_vault_compactor.dart';
import 'package:sinapsis/features/vault/domain/entities/compaction_assessment.dart';
import 'package:sinapsis/features/vault/domain/entities/compaction_progress.dart';
import 'package:sinapsis/features/vault/domain/services/free_space_probe.dart';
import 'package:sinapsis/features/vault/domain/services/vault_compactor.dart';

import '../../../../support/test_vault.dart';

class _FakeDisk implements FreeSpaceProbe {
  int? free = 1 << 40;

  @override
  Future<int?> freeBytesAt(String path) async => free;
}

/// Todas las tablas que una compactación tiene que dejar con las mismas filas.
const _allTables = [
  ...VaultCounts.userDataTables,
  ...VaultCounts.modelTables,
  ...VaultCounts.durabilityTables,
  ...VaultCounts.referenceTables,
];

/// Corre contra una bóveda de verdad en un archivo, con fuentes, chunks y los
/// índices de búsqueda: lo que se compacta es lo que la app guarda, no una
/// tabla de relleno.
void main() {
  late Directory dir;
  late File file;
  late TestVault vault;
  late _FakeDisk disk;
  late SqliteCompactionAdvisor advisor;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sinapsis_compactor_');
    file = File(p.join(dir.path, 'sinapsis.sqlite'));
    vault = await TestVault.onFile(file, deviceId: 'tel');
    disk = _FakeDisk();
    advisor = SqliteCompactionAdvisor(database: vault.db, freeSpace: disk);
  });

  tearDown(() async {
    await vault.dispose();
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  SqliteVaultCompactor compactor({int stepPages = 8}) => SqliteVaultCompactor(
    database: vault.db,
    advisor: advisor,
    stepPages: stepPages,
  );

  /// El texto de la fuente [n]: una palabra que solo ella tiene, seguida de
  /// relleno de cada largo para que ocupe varias páginas.
  String textOf(int n) {
    final filler = List.generate(400, (i) => 'palabra$i de la fuente $n');
    return 'zorro$n. ${filler.join('. ')}';
  }

  Future<List<String>> seed(int sources) async {
    final ids = <String>[];
    for (var n = 0; n < sources; n++) {
      final id = 'src-${n.toString().padLeft(3, '0')}';
      await vault.saveSource(id, text: textOf(n));
      ids.add(id);
    }
    return ids;
  }

  /// Manda a la papelera y vacía: lo que se borra de verdad deja páginas
  /// libres.
  Future<void> erase(Iterable<String> ids) async {
    await vault.library.deleteMany(ids.toList());
    await vault.library.emptyTrash();
  }

  Future<int> pragma(String name) async =>
      (await vault.db.customSelect('PRAGMA $name').getSingle()).read<int>(name);

  Future<int> hits(String token) async =>
      (await vault.db
              .customSelect(
                'SELECT rowid FROM chunk_search WHERE chunk_search MATCH ?',
                variables: [Variable<String>(token)],
              )
              .get())
          .length;

  Future<VaultCounts> counts() =>
      captureVaultCounts(vault.db, tables: _allTables);

  group('la primera compactación reescribe la bóveda entera', () {
    late List<String> kept;
    late CompactionAssessment before;
    late VaultCounts countsBefore;

    setUp(() async {
      final ids = await seed(40);
      await erase(ids.take(30));
      kept = ids.skip(30).toList();
      before = await advisor.assess();
      countsBefore = await counts();
    });

    test(
      'la deja más chica, en modo incremental y sin páginas libres',
      () async {
        expect(before.needsFullRewrite, isTrue);
        expect(before.freePages, greaterThan(0));

        final result = await compactor().compact();

        expect(result.wasCancelled, isFalse);
        expect(result.bytesBefore, before.fileBytes);
        expect(result.bytesAfter, file.lengthSync());
        expect(result.bytesAfter, lessThan(result.bytesBefore));
        // Queda cerca de lo que la base tiene de verdad —lo que sobra son las
        // páginas del mapa de punteros del modo incremental—.
        expect(
          result.bytesAfter,
          lessThanOrEqualTo(before.usefulBytes + 16 * before.pageSize),
        );
        final after = await advisor.assess();
        expect(after.autoVacuum, AutoVacuumMode.incremental);
        expect(after.freePages, 0);
        expect(after.needsFullRewrite, isFalse);
      },
    );

    test('cada tabla queda con las mismas filas', () async {
      await compactor().compact();

      expect(countsBefore.differencesWith(await counts()), isEmpty);
    });

    test('el texto de cada fuente sigue íntegro y se comprueba', () async {
      final result = await compactor().compact();

      for (final id in kept) {
        final n = int.parse(id.substring(4));
        expect((await sourceTextRendition(vault.db, id))?.content, textOf(n));
      }
      expect(result.sourcesVerified, kept.length);
    });

    test(
      'la búsqueda sigue encontrando lo que queda y nada de lo borrado',
      () async {
        expect(await hits('zorro35'), 1);

        await compactor().compact();

        expect(await hits('zorro35'), 1);
        expect(await hits('zorro3'), 0, reason: 'zorro3 se borró');
        // El índice sigue coincidiendo con la tabla de chunks, fila por fila.
        await vault.db.customStatement(
          "INSERT INTO chunk_search(chunk_search) VALUES('integrity-check')",
        );
        final check = await vault.db
            .customSelect('PRAGMA integrity_check')
            .getSingle();
        expect(check.read<String>('integrity_check'), 'ok');
      },
    );

    test('avisa las fases, en orden: medir, reescribir, comprobar', () async {
      final progress = <CompactionProgress>[];

      await compactor().compact(onProgress: progress.add);

      final phases = progress.map((p) => p.phase).toList();
      expect(phases.first, CompactionPhase.checking);
      expect(phases, contains(CompactionPhase.rewriting));
      expect(phases.last, CompactionPhase.verifying);
      expect(
        phases.indexOf(CompactionPhase.rewriting),
        lessThan(phases.lastIndexOf(CompactionPhase.verifying)),
      );
      // La comprobación termina diciendo que revisó todo.
      expect(progress.last.done, progress.last.total);
      expect(progress.last.total, kept.length);
      // Y reescribir no informa avance —es una sola operación—.
      expect(
        progress
            .firstWhere((p) => p.phase == CompactionPhase.rewriting)
            .fraction,
        isNull,
      );
    });

    test('los temporales de SQLite vuelven a lo de siempre', () async {
      await compactor().compact();

      // 0 es «el valor por omisión»; 1, archivo; 2, memoria.
      expect(await pragma('temp_store'), 0);
    });

    test('sin dato de disco se intenta igual', () async {
      disk.free = null;

      final result = await compactor().compact();

      expect(result.freedBytes, greaterThan(0));
    });
  });

  group('las compactaciones siguientes devuelven de a tramos', () {
    late List<String> kept;

    setUp(() async {
      final ids = await seed(40);
      await erase(ids.take(20));
      await compactor().compact();
      // Ahora la bóveda ya está en modo incremental. Se borra más.
      await erase(ids.skip(20).take(10));
      kept = ids.skip(30).toList();
    });

    test(
      'sin reescribir: en pasos, con su avance, hasta no dejar ninguna',
      () async {
        final before = await advisor.assess();
        expect(before.needsFullRewrite, isFalse);
        expect(before.freePages, greaterThan(8));
        final progress = <CompactionProgress>[];

        final result = await compactor().compact(onProgress: progress.add);

        final returning = progress
            .where((p) => p.phase == CompactionPhase.returning)
            .toList();
        expect(
          progress.map((p) => p.phase),
          isNot(contains(CompactionPhase.rewriting)),
        );
        // Más de un tramo, y cada aviso va más adelante que el anterior.
        expect(returning.length, greaterThan(2));
        for (var i = 1; i < returning.length; i++) {
          expect(returning[i].done, greaterThan(returning[i - 1].done));
        }
        expect(returning.last.done, before.freePages);
        expect(returning.last.fraction, 1.0);
        expect(returning.first.total, before.freePages);

        final after = await advisor.assess();
        expect(after.freePages, 0);
        expect(after.autoVacuum, AutoVacuumMode.incremental);
        expect(result.bytesAfter, lessThan(result.bytesBefore));
        expect(result.sourcesVerified, kept.length);
      },
    );

    test(
      'cancelar entre dos tramos deja lo devuelto y la bóveda completa',
      () async {
        final before = await advisor.assess();
        final countsBefore = await counts();
        final cancellation = CompactionCancellation();

        final result = await compactor().compact(
          cancellation: cancellation,
          onProgress: (progress) {
            if (progress.phase == CompactionPhase.returning &&
                progress.done > 0) {
              cancellation.cancel();
            }
          },
        );

        expect(result.wasCancelled, isTrue);
        // Devolvió algo pero no todo, y no se hizo esperar con la
        // comprobación larga: solo se contaron las filas.
        final partway = await advisor.assess();
        expect(partway.freePages, lessThan(before.freePages));
        expect(partway.freePages, greaterThan(0));
        expect(result.bytesAfter, lessThan(result.bytesBefore));
        expect(result.sourcesVerified, 0);
        expect(countsBefore.differencesWith(await counts()), isEmpty);
        final check = await vault.db
            .customSelect('PRAGMA integrity_check')
            .getSingle();
        expect(check.read<String>('integrity_check'), 'ok');

        // Y se puede seguir: la siguiente vez sigue desde donde quedó.
        final rest = await compactor().compact();
        expect(rest.wasCancelled, isFalse);
        expect((await advisor.assess()).freePages, 0);
      },
    );
  });

  group('lo que no debe cambiar nada', () {
    test(
      'sin espacio en el disco, no toca la bóveda y dice cuánto falta',
      () async {
        final ids = await seed(20);
        await erase(ids.take(15));
        final sizeBefore = file.lengthSync();
        final modeBefore = await pragma('auto_vacuum');
        disk.free = 1024;

        await expectLater(
          compactor().compact(),
          throwsA(
            isA<VaultCompactionNoSpaceException>().having(
              (e) => e.assessment.missingBytes,
              'lo que falta',
              greaterThan(0),
            ),
          ),
        );

        expect(file.lengthSync(), sizeBefore);
        expect(await pragma('auto_vacuum'), modeBefore);
      },
    );

    test('sin nada que recuperar, no hace nada y no lo simula', () async {
      final progress = <CompactionProgress>[];
      // La base se abre sola con la primera consulta: el archivo existe desde
      // que alguien la mide.
      await advisor.assess();
      final sizeBefore = file.lengthSync();

      final result = await compactor().compact(onProgress: progress.add);

      expect(result.freedBytes, 0);
      expect(result.sourcesVerified, 0);
      expect(progress.map((p) => p.phase), [CompactionPhase.checking]);
      expect(file.lengthSync(), sizeBefore);
      expect(await pragma('auto_vacuum'), 0);
    });

    test('si ya se pidió parar antes de empezar, no empieza', () async {
      final ids = await seed(20);
      await erase(ids.take(15));
      final sizeBefore = file.lengthSync();
      final cancellation = CompactionCancellation()..cancel();

      final result = await compactor().compact(cancellation: cancellation);

      expect(result.wasCancelled, isTrue);
      expect(file.lengthSync(), sizeBefore);
      expect(await pragma('auto_vacuum'), 0);
    });
  });

  group('la comprobación de después', () {
    late List<String> ids;

    setUp(() async {
      ids = await seed(20);
      await erase(ids.take(10));
    });

    test(
      'si una tabla cambió de filas, NO da la compactación por buena',
      () async {
        await expectLater(
          compactor().compact(
            onProgress: (progress) {
              // Justo antes de contar lo de después: se pierde una fila,
              // como si la compactación hubiera dejado algo atrás.
              if (progress.phase == CompactionPhase.verifying &&
                  progress.total == 0) {
                unawaited(
                  vault.db.customStatement('DELETE FROM chunks WHERE seq = 0'),
                );
              }
            },
          ),
          throwsA(
            isA<VaultCompactionVerificationException>().having(
              (e) => e.problem,
              'qué difiere',
              allOf(contains('chunks'), contains('→')),
            ),
          ),
        );
      },
    );

    test('si el texto ya no se reconstruye con sus chunks, tampoco', () async {
      await expectLater(
        compactor().compact(
          onProgress: (progress) {
            // Con la cuenta de filas ya pasada, antes de leer la primera
            // fuente.
            if (progress.phase == CompactionPhase.verifying &&
                progress.total > 0 &&
                progress.done == 0) {
              unawaited(
                vault.db.customStatement(
                  "UPDATE chunks SET content = content || 'x'",
                ),
              );
            }
          },
        ),
        throwsA(
          isA<VaultCompactionVerificationException>().having(
            (e) => e.problem,
            'qué difiere',
            contains('violaciones'),
          ),
        ),
      );
    });
  });
}
