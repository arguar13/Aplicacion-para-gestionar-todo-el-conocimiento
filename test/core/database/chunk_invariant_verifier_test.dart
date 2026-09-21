import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/chunk_invariant_verifier.dart';
import 'package:sinapsis/core/database/knowledge_source_chunking.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';

import '../../support/fake_id_generator.dart';
import '../../support/in_memory_file_store.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Contra SQLite real, en memoria, con una bóveda sembrada por el mismo
/// camino que la app: `LibraryRepositoryImpl.save` y después
/// `chunkAndPersistSource`, el fragmentador que corre en producción.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late FakeIdGenerator ids;

  final now = DateTime(2026, 9, 19, 10);
  var counter = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    ids = FakeIdGenerator();
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
    );
    counter = 0;
  });

  tearDown(() => db.close());

  Future<String> seedSource({
    required String text,
    RenditionKind kind = RenditionKind.markdown,
    SourceKind sourceKind = SourceKind.webPage,
    bool chunk = true,
  }) async {
    final n = counter++;
    final itemId = 'item-$n';
    await library.save(
      KnowledgeItem(
        id: itemId,
        title: 'Fuente $n',
        source: Source(
          id: 'src-$n',
          kind: sourceKind,
          capturedAt: now,
          url: 'https://ejemplo.org/$n',
        ),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
        renditions: text.isEmpty
            ? const []
            : [
                Rendition.text(
                  id: 'rend-$n',
                  itemId: itemId,
                  kind: kind,
                  content: text,
                  isPrimary: true,
                  createdAt: now,
                ),
              ],
      ),
    );
    if (chunk) await chunkAndPersistSource(db, itemId: itemId, ids: ids);
    return itemId;
  }

  /// Una bóveda con los tipos de texto que el fragmentador distingue —y
  /// los casos que más fácilmente rompen offsets: acentos, un emoji (par
  /// sustituto en UTF-16), CRLF y una transcripción con marcas de tiempo—.
  Future<Map<String, String>> seedVault() async {
    final article = await seedSource(
      text:
          '# Título del artículo\n\nPrimer párrafo, con acentos: canción, '
          'niño, pingüino.\n\nUn párrafo con emoji 🌍 y más texto.\n\n'
          'Cierre sin salto final',
    );
    final transcript = await seedSource(
      text:
          '[00:00] Hola a todos.\n[00:20] Hoy hablamos de Roma.\n'
          '[00:40] Empezó como una aldea\n[01:00] a orillas del Tíber.\n'
          '[01:20] Después vino la república.\n[01:40] Y luego el imperio.\n'
          '[02:00] Fin de la primera parte.\n[02:20] Gracias por ver.',
      sourceKind: SourceKind.youtube,
    );
    final crlf = await seedSource(
      text: 'Línea uno\r\n\r\nLínea dos\r\n\r\nLínea tres\r\n',
      kind: RenditionKind.plainText,
      sourceKind: SourceKind.document,
    );
    // Sin texto todavía: ni pasa ni falla.
    await seedSource(text: '', sourceKind: SourceKind.audio);
    // Una nota: no tiene chunks ni `fullText`, no entra en la verificación.
    await library.save(
      KnowledgeItem(
        id: 'nota-1',
        title: 'Una nota',
        source: Source(
          id: 'src-nota',
          kind: SourceKind.manualNote,
          capturedAt: now,
        ),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
      ),
    );
    return {'article': article, 'transcript': transcript, 'crlf': crlf};
  }

  test(
    'una bóveda sana cumple el invariante y cuenta lo que comprobó',
    () async {
      await seedVault();

      final report = await verifyChunkInvariant(db);

      expect(report.holds, isTrue, reason: report.violations.join('\n'));
      expect(report.sourcesChecked, 3);
      expect(report.sourcesWithoutText, 1);
      expect(report.chunksChecked, greaterThan(3));
      expect(report.summary(), contains('invariante OK'));
    },
  );

  group('el aviso de avance', () {
    test('avisa al empezar, cada tanto y al terminar', () async {
      // Más fuentes que el intervalo: 60 con el intervalo de 25.
      for (var i = 0; i < 60; i++) {
        await seedSource(text: 'Texto de la fuente número $i.');
      }
      final calls = <(int, int)>[];

      final report = await verifyChunkInvariant(
        db,
        onProgress: (checked, total) => calls.add((checked, total)),
      );

      expect(report.sourcesChecked, 60);
      expect(calls, [(0, 60), (25, 60), (50, 60), (60, 60)]);
    });

    test('una bóveda vacía avisa una sola vez, ya terminada', () async {
      final calls = <(int, int)>[];

      await verifyChunkInvariant(
        db,
        onProgress: (checked, total) => calls.add((checked, total)),
      );

      expect(calls, [(0, 0)]);
    });

    test('sin aviso pedido, no cambia nada', () async {
      await seedVault();

      final report = await verifyChunkInvariant(db);

      expect(report.holds, isTrue);
    });
  });

  test('una bóveda vacía cumple el invariante sin comprobar nada', () async {
    final report = await verifyChunkInvariant(db);

    expect(report.holds, isTrue);
    expect(report.sourcesChecked, 0);
    expect(report.chunksChecked, 0);
  });

  test('un chunk alterado se detecta como texto y offsets distintos', () async {
    final vault = await seedVault();
    final chunk =
        await (db.select(db.chunks)
              ..where((c) => c.itemId.equals(vault['article']!))
              ..orderBy([(c) => OrderingTerm(expression: c.seq)])
              ..limit(1))
            .getSingle();
    await (db.update(db.chunks)..where((c) => c.id.equals(chunk.id))).write(
      const ChunksCompanion(content: Value('texto resumido')),
    );

    final report = await verifyChunkInvariant(db);

    expect(report.holds, isFalse);
    final problems = report.violations
        .where((v) => v.itemId == vault['article'])
        .map((v) => v.problem)
        .toSet();
    expect(problems, {
      ChunkInvariantProblem.textMismatch,
      ChunkInvariantProblem.offsetsInconsistent,
    });
    // Las demás fuentes no se ven afectadas.
    expect(
      report.violations.where((v) => v.itemId != vault['article']),
      isEmpty,
    );
  });

  group('con onlyItemIds', () {
    Future<void> corrupt(String itemId) =>
        (db.update(db.chunks)..where((c) => c.itemId.equals(itemId))).write(
          const ChunksCompanion(content: Value('texto resumido')),
        );

    test('mira solo esas fuentes: el daño en otra no cuenta', () async {
      final vault = await seedVault();
      await corrupt(vault['article']!);

      final others = await verifyChunkInvariant(
        db,
        onlyItemIds: [vault['transcript']!, vault['crlf']!],
      );
      final damaged = await verifyChunkInvariant(
        db,
        onlyItemIds: [vault['article']!],
      );

      expect(others.holds, isTrue);
      expect(others.sourcesChecked, 2);
      expect(damaged.holds, isFalse);
      expect(damaged.sourcesChecked, 1);
    });

    test('ignora lo que no es una fuente y lo que no existe', () async {
      final vault = await seedVault();

      final report = await verifyChunkInvariant(
        db,
        onlyItemIds: ['nota-1', 'no-existe', vault['crlf']!],
      );

      expect(report.holds, isTrue);
      expect(report.sourcesChecked, 1);
    });

    test('una lista vacía no comprueba nada', () async {
      await seedVault();

      final report = await verifyChunkInvariant(db, onlyItemIds: const []);

      expect(report.sourcesChecked, 0);
      expect(report.chunksChecked, 0);
    });

    test('con más ids que el tope de una consulta, sigue sirviendo', () async {
      final vault = await seedVault();
      final many = [
        for (var i = 0; i < 900; i++) 'fantasma-$i',
        vault['article']!,
      ];

      final report = await verifyChunkInvariant(db, onlyItemIds: many);

      expect(report.sourcesChecked, 1);
    });
  });

  test('un chunk faltante en el medio rompe la secuencia y el texto', () async {
    final vault = await seedVault();
    final chunks =
        await (db.select(db.chunks)
              ..where((c) => c.itemId.equals(vault['transcript']!))
              ..orderBy([(c) => OrderingTerm(expression: c.seq)]))
            .get();
    expect(chunks.length, greaterThan(1));
    await (db.delete(
      db.chunks,
    )..where((c) => c.id.equals(chunks.first.id))).go();

    final report = await verifyChunkInvariant(db);

    final problems = report.violations
        .where((v) => v.itemId == vault['transcript'])
        .map((v) => v.problem)
        .toSet();
    expect(problems, contains(ChunkInvariantProblem.seqNotContiguous));
    expect(problems, contains(ChunkInvariantProblem.textMismatch));
  });

  test('una fuente con texto y sin ningún chunk se detecta', () async {
    final vault = await seedVault();
    await (db.delete(
      db.chunks,
    )..where((c) => c.itemId.equals(vault['crlf']!))).go();

    final report = await verifyChunkInvariant(db);

    expect(
      report.violations.map((v) => (v.itemId, v.problem)),
      contains((vault['crlf'], ChunkInvariantProblem.missingChunks)),
    );
  });

  test('offsets corridos con el texto intacto se detectan aparte', () async {
    final vault = await seedVault();
    final first =
        await (db.select(db.chunks)
              ..where((c) => c.itemId.equals(vault['article']!))
              ..orderBy([(c) => OrderingTerm(expression: c.seq)])
              ..limit(1))
            .getSingle();
    await (db.update(db.chunks)..where((c) => c.id.equals(first.id))).write(
      ChunksCompanion(charEnd: Value(first.charEnd - 1)),
    );

    final report = await verifyChunkInvariant(db);

    expect(report.violations.map((v) => v.problem).toSet(), {
      ChunkInvariantProblem.offsetsInconsistent,
    });
  });
}
