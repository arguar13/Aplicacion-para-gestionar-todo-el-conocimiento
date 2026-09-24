import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/reference/data/repositories/reference_identity_repository_impl.dart';

import '../../../../support/fake_id_generator.dart';

/// Contra SQLite real: el índice de identidad de una importación (F15, D9).
void main() {
  late AppDatabase db;
  late KnowledgeEntryWriter writer;
  late ReferenceIdentityRepositoryImpl repository;
  final capturedAt = DateTime(2026, 9, 24, 10);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), deviceId: 'telefono');
    writer = KnowledgeEntryWriter(
      db,
      clock: () => DateTime(2026, 9, 24, 11),
      ids: FakeIdGenerator(prefix: 'persona'),
    );
    repository = ReferenceIdentityRepositoryImpl(db);
  });

  tearDown(() => db.close());

  Future<void> source(
    String id, {
    SourceKind kind = SourceKind.reference,
    String? url,
    ReferenceData reference = const ReferenceData(),
  }) async {
    await writer.upsert(
      KnowledgeItem(
        id: id,
        title: 'Título $id',
        source: Source(
          id: 'src-$id',
          kind: kind,
          capturedAt: capturedAt,
          url: url,
        ),
        processingState: ProcessingState.ready,
        createdAt: capturedAt,
        updatedAt: capturedAt,
      ),
    );
    if (!reference.isEmpty) await writer.setReference(id, reference);
  }

  Future<void> trash(String id) =>
      (db.update(db.knowledgeEntries)..where((e) => e.id.equals(id))).write(
        KnowledgeEntriesCompanion(deletedAt: Value(DateTime(2026, 9, 24))),
      );

  test('encuentra por DOI', () async {
    await source('a', reference: const ReferenceData(doi: '10.1000/xyz'));

    final index = await repository.buildIndex();

    expect(index.find(doi: '10.1000/xyz'), 'a');
  });

  test('encuentra por ISBN', () async {
    await source('a', reference: const ReferenceData(isbn: '9780306406157'));

    final index = await repository.buildIndex();

    expect(index.find(isbn: '9780306406157'), 'a');
  });

  test('encuentra por URL, sin importar cómo esté escrita', () async {
    await source('a', url: 'https://www.ejemplo.org/articulo/');

    final index = await repository.buildIndex();

    expect(index.find(url: 'https://ejemplo.org/articulo'), 'a');
  });

  test('deja afuera lo que está en la papelera', () async {
    await source('a', reference: const ReferenceData(doi: '10.1000/xyz'));
    await trash('a');

    final index = await repository.buildIndex();

    expect(index.find(doi: '10.1000/xyz'), isNull);
  });

  test('sin nada con identificadores, un índice vacío que no rompe', () async {
    await source('a');

    final index = await repository.buildIndex();

    expect(index.find(doi: 'x', isbn: 'y', url: 'https://z.org'), isNull);
  });

  test('varias fuentes, cada una con lo suyo', () async {
    await source('a', reference: const ReferenceData(doi: '10.1000/a'));
    await source('b', reference: const ReferenceData(isbn: '9780306406157'));
    await source('c', url: 'https://ejemplo.org/c');

    final index = await repository.buildIndex();

    expect(index.find(doi: '10.1000/a'), 'a');
    expect(index.find(isbn: '9780306406157'), 'b');
    expect(index.find(url: 'https://ejemplo.org/c'), 'c');
  });
}
