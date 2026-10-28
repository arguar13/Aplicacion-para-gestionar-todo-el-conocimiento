import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/citations/data/repositories/bibliography_repository_impl.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';

import '../../../../support/in_memory_file_store.dart';
import '../../../../support/item_rows.dart';
import '../../../../support/processed_rows.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Lo procesado como corpus de una consulta (F41, paso 6): lo que leen el
/// Atlas, el Mapa, el grafo local y la Línea de tiempo. Los mismos filtros de
/// la Biblioteca, sobre los documentos procesados y nada más; el texto, en lo
/// que la persona eligió; el tipo, el de la fuente.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  final now = DateTime(2026, 9, 21, 10);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
    );
    await insertItemRows(db, id: 'fuente', title: 'Darwin, la fuente');
    await insertProcessedDocument(
      db,
      id: 'p-darwin',
      title: 'Darwin',
      createdAt: now,
      sourceKind: SourceKind.document,
      text: 'El origen de las especies cambió la biología.',
    );
    await insertProcessedDocument(
      db,
      id: 'p-video',
      title: 'Un video sobre Kuhn',
      createdAt: now,
      sourceKind: SourceKind.youtube,
      sections: {ProcessedSection.text, ProcessedSection.notes},
      text: 'Kuhn habla del paradigma.',
    );
  });

  tearDown(() => db.close());

  Future<List<String>> ids(LibraryQuery query) async =>
      (await library.matchingIds(query)).getOrElse((f) => fail('$f'));

  test('la Biblioteca deja afuera lo procesado, y lo procesado deja afuera la '
      'Biblioteca', () async {
    expect(await ids(const LibraryQuery()), ['fuente']);
    expect(
      (await ids(const LibraryQuery(scope: LibraryScope.processed))).toSet(),
      {'p-darwin', 'p-video'},
    );
  });

  test('el texto se busca en lo que se eligió, cada palabra en cualquier '
      'parte', () async {
    expect(
      await ids(
        const LibraryQuery(
          searchText: 'biología',
          scope: LibraryScope.processed,
        ),
      ),
      ['p-darwin'],
    );
    expect(
      await ids(
        const LibraryQuery(
          searchText: 'kuhn paradigma',
          scope: LibraryScope.processed,
        ),
      ),
      ['p-video'],
    );
    // «Darwin» está en el título de la fuente y del procesado: solo sale este.
    expect(
      await ids(
        const LibraryQuery(searchText: 'darwin', scope: LibraryScope.processed),
      ),
      ['p-darwin'],
    );
    // Unas comillas solas se buscan tal cual, y ninguna parte las tiene.
    expect(
      await ids(
        const LibraryQuery(searchText: '""', scope: LibraryScope.processed),
      ),
      isEmpty,
    );
  });

  test('el tipo es el de la fuente de la que salió', () async {
    expect(
      await ids(
        const LibraryQuery(
          sourceKinds: {SourceKind.youtube},
          scope: LibraryScope.processed,
        ),
      ),
      ['p-video'],
    );
  });

  test('«solo estos» respeta el lado: un id de la Biblioteca no se '
      'cuela', () async {
    expect(
      await ids(
        const LibraryQuery(
          ids: {'fuente', 'p-darwin'},
          scope: LibraryScope.processed,
        ),
      ),
      ['p-darwin'],
    );
  });

  test('la bibliografía de lo procesado es la de sus fuentes', () async {
    await (db.update(
      db.processedDocuments,
    )..where((d) => d.itemId.equals('p-darwin'))).write(
      const ProcessedDocumentsCompanion(sourceItemId: Value('fuente')),
    );

    final sources = await BibliographyRepositoryImpl(
      db,
    ).sourcesMatching(const LibraryQuery(scope: LibraryScope.processed));

    // El del video no tiene fuente: se borró de verdad, y no hay a quién citar.
    expect([for (final s in sources) s.itemId], ['fuente']);
  });
}
