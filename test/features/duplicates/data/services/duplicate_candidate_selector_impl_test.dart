import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/source_processing_status.dart';
import 'package:sinapsis/features/duplicates/data/services/duplicate_candidate_selector_impl.dart';
import 'package:sinapsis/features/duplicates/domain/services/duplicate_candidate_selector.dart';

/// Contra SQLite real, en memoria, sembrando `KnowledgeEntries`/
/// `KnowledgeSources`/`KnowledgeNotes` directo a mano con huellas de
/// juguete —hex de 16 caracteres (64 bits), como las que produce
/// `DedupFingerprint.simhashOf`—.
void main() {
  late AppDatabase db;
  late DuplicateCandidateSelectorImpl selector;

  final now = DateTime(2026, 9, 19, 10);
  var counter = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    selector = DuplicateCandidateSelectorImpl(database: db);
    counter = 0;
  });

  tearDown(() => db.close());

  Future<String> seedSource({
    required String title,
    String? dedupHash,
    String? simhash,
  }) async {
    final itemId = 'item-${counter++}';
    await db
        .into(db.knowledgeEntries)
        .insert(
          KnowledgeEntriesCompanion.insert(
            id: itemId,
            title: title,
            kind: ItemKind.source,
            state: ItemState.processed,
            createdAt: now,
            updatedAt: now,
            deviceId: 'test',
          ),
        );
    await db
        .into(db.knowledgeSources)
        .insert(
          KnowledgeSourcesCompanion.insert(
            itemId: itemId,
            sourceType: SourceKind.webPage,
            capturedAt: now,
            contentHash: 'raw-hash-$itemId',
            processingStatus: SourceProcessingStatus.done,
            dedupHash: Value(dedupHash),
            simhash: Value(simhash),
          ),
        );
    return itemId;
  }

  Future<String> seedNote({
    required String title,
    String? dedupHash,
    String? simhash,
  }) async {
    final itemId = 'item-${counter++}';
    await db
        .into(db.knowledgeEntries)
        .insert(
          KnowledgeEntriesCompanion.insert(
            id: itemId,
            title: title,
            kind: ItemKind.note,
            state: ItemState.captured,
            createdAt: now,
            updatedAt: now,
            deviceId: 'test',
          ),
        );
    await db
        .into(db.knowledgeNotes)
        .insert(
          KnowledgeNotesCompanion.insert(
            itemId: itemId,
            noteKind: NoteKind.living,
            maturity: NoteMaturity.seed,
            dedupHash: Value(dedupHash),
            simhash: Value(simhash),
          ),
        );
    return itemId;
  }

  test('sin dedupHash el semilla, lista vacía', () async {
    final seedId = await seedSource(title: 'Sin fingerprint todavía');

    final result = await selector.selectCandidates(seedItemId: seedId);

    expect(result, isEmpty);
  });

  test('una coincidencia exacta se encuentra', () async {
    final seedId = await seedSource(
      title: 'Semilla',
      dedupHash: 'hash-a',
      simhash: '0000000000000000',
    );
    final duplicateId = await seedSource(
      title: 'Idéntico',
      dedupHash: 'hash-a',
      simhash: '0000000000000000',
    );

    final result = await selector.selectCandidates(seedItemId: seedId);

    expect(result, hasLength(1));
    expect(result.single.itemId, duplicateId);
    expect(result.single.matchKind, DuplicateMatchKind.exact);
    expect(result.single.hammingDistance, 0);
  });

  test('un casi-duplicado dentro del umbral se encuentra', () async {
    final seedId = await seedSource(
      title: 'Semilla',
      dedupHash: 'hash-a',
      simhash: '0000000000000000',
    );
    // Difiere en 2 bits del semilla (0x3 = 0b11): dentro del umbral
    // por defecto (distancia <= 3).
    final nearId = await seedSource(
      title: 'Casi igual',
      dedupHash: 'hash-b',
      simhash: '0000000000000003',
    );

    final result = await selector.selectCandidates(seedItemId: seedId);

    expect(result, hasLength(1));
    expect(result.single.itemId, nearId);
    expect(result.single.matchKind, DuplicateMatchKind.near);
    expect(result.single.hammingDistance, 2);
  });

  test('fuera del umbral no se encuentra', () async {
    final seedId = await seedSource(
      title: 'Semilla',
      dedupHash: 'hash-a',
      simhash: '0000000000000000',
    );
    // Los 64 bits difieren: muy lejos del umbral por defecto.
    await seedSource(
      title: 'Sin relación',
      dedupHash: 'hash-c',
      simhash: 'ffffffffffffffff',
    );

    final result = await selector.selectCandidates(seedItemId: seedId);

    expect(result, isEmpty);
  });

  test('un elemento no se compara consigo mismo', () async {
    final seedId = await seedSource(
      title: 'Semilla',
      dedupHash: 'hash-a',
      simhash: '0000000000000000',
    );

    final result = await selector.selectCandidates(seedItemId: seedId);

    expect(result.map((c) => c.itemId), isNot(contains(seedId)));
  });

  test(
    'funciona entre fuentes y notas mezcladas, cualquier combinación',
    () async {
      final seedId = await seedNote(
        title: 'Una nota',
        dedupHash: 'hash-a',
        simhash: '0000000000000000',
      );
      final duplicateSourceId = await seedSource(
        title: 'La misma idea, capturada como fuente',
        dedupHash: 'hash-a',
        simhash: '0000000000000000',
      );

      final result = await selector.selectCandidates(seedItemId: seedId);

      expect(result, hasLength(1));
      expect(result.single.itemId, duplicateSourceId);
    },
  );
}
