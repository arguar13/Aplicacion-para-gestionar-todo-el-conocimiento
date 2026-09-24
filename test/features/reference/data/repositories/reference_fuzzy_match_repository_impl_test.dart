import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/reference/data/repositories/reference_fuzzy_match_repository_impl.dart';

import '../../../../support/fake_id_generator.dart';

/// Contra SQLite real: el índice de coincidencia difusa al importar (F15, D9).
void main() {
  late AppDatabase db;
  late KnowledgeEntryWriter writer;
  late ReferenceFuzzyMatchRepositoryImpl repository;
  final capturedAt = DateTime(2026, 9, 24, 10);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), deviceId: 'telefono');
    writer = KnowledgeEntryWriter(
      db,
      clock: () => DateTime(2026, 9, 24, 11),
      ids: FakeIdGenerator(prefix: 'persona'),
    );
    repository = ReferenceFuzzyMatchRepositoryImpl(db);
  });

  tearDown(() => db.close());

  Future<void> source(
    String id, {
    required String title,
    SourceKind kind = SourceKind.reference,
    DateTime? publishedAt,
    List<Contributor> contributors = const [],
  }) async {
    await writer.upsert(
      KnowledgeItem(
        id: id,
        title: title,
        source: Source(
          id: 'src-$id',
          kind: kind,
          capturedAt: capturedAt,
          publishedAt: publishedAt,
        ),
        processingState: ProcessingState.ready,
        createdAt: capturedAt,
        updatedAt: capturedAt,
      ),
    );
    if (contributors.isNotEmpty) {
      await writer.setReference(id, ReferenceData(contributors: contributors));
    }
  }

  Future<void> trash(String id) =>
      (db.update(db.knowledgeEntries)..where((e) => e.id.equals(id))).write(
        KnowledgeEntriesCompanion(deletedAt: Value(DateTime(2026, 9, 24))),
      );

  test('arma un candidato con título, año y primer autor', () async {
    await source(
      'a',
      title: 'Cien años de soledad',
      publishedAt: DateTime(1967),
      contributors: const [
        Contributor(
          name: PersonName(family: 'García Márquez', given: 'Gabriel'),
        ),
      ],
    );

    final index = await repository.buildIndex();

    final found = index.find(title: 'Cien años de soledad', year: 1967);
    expect(found, hasLength(1));
    expect(found.single.firstAuthorFamily, 'garcia marquez');
  });

  test('toma al PRIMER autor, no a cualquiera', () async {
    await source(
      'a',
      title: 'Un libro con dos autores',
      contributors: const [
        Contributor(name: PersonName(family: 'Segundo')),
        Contributor(name: PersonName(family: 'Primero')),
      ],
    );
    // El orden real lo decide `position`, que el escritor asigna según el
    // orden de la lista: 'Segundo' queda en 0, 'Primero' en 1. El primer
    // autor es 'Segundo'.

    final index = await repository.buildIndex();

    expect(
      index.find(title: 'Un libro con dos autores').single.firstAuthorFamily,
      'segundo',
    );
  });

  test('una obra sin autor: candidato sin firstAuthorFamily', () async {
    await source('a', title: 'Anónimo');

    final index = await repository.buildIndex();

    expect(index.find(title: 'Anónimo').single.firstAuthorFamily, isNull);
  });

  test('deja afuera lo que está en la papelera', () async {
    await source('a', title: 'Se va a borrar');
    await trash('a');

    final index = await repository.buildIndex();

    expect(index.find(title: 'Se va a borrar'), isEmpty);
  });

  test('varias obras con el mismo título quedan juntas', () async {
    await source('a', title: 'Título repetido', publishedAt: DateTime(2000));
    await source('b', title: 'Título repetido', publishedAt: DateTime(2010));

    final index = await repository.buildIndex();

    expect(index.find(title: 'Título repetido'), hasLength(2));
    expect(index.find(title: 'Título repetido', year: 2000), hasLength(1));
  });
}
