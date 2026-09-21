import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/reference/data/repositories/reference_repository_impl.dart';

class _MockTelemetry extends Mock implements TelemetryService {}

/// El repositorio de la referencia de una fuente (F15), contra SQLite real:
/// guarda por el escritor único, resuelve las personas contra el vocabulario y
/// se vuelve a emitir cuando cambia lo que muestra.
void main() {
  late AppDatabase db;
  late ReferenceRepositoryImpl repository;
  final now = DateTime(2026, 9, 21, 9);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), deviceId: 'telefono');
    repository = ReferenceRepositoryImpl(
      database: db,
      telemetry: _MockTelemetry(),
      clock: () => now,
    );
    final writer = KnowledgeEntryWriter(db, clock: () => now);
    await writer.upsert(_item('libro'));
    await writer.upsert(_item('otro'));
    await writer.upsert(_item('nota', kind: SourceKind.manualNote));
  });

  tearDown(() => db.close());

  const garcia = PersonName(family: 'García Márquez', given: 'Gabriel');

  group('guardar', () {
    test('lo que se guarda vuelve tal cual, con sus personas', () async {
      final saved = await repository.saveReference(
        'libro',
        const ReferenceData(
          type: ReferenceType.book,
          publisher: 'Sudamericana',
          isbn: '978-0-306-40615-7',
          contributors: [
            Contributor(name: garcia),
            Contributor(
              name: PersonName(family: 'Rabassa', given: 'Gregory'),
              role: ContributorRole.translator,
            ),
          ],
        ),
      );

      final read = await repository.read('libro');

      expect(saved, isTrue);
      expect(read.type, ReferenceType.book);
      expect(read.publisher, 'Sudamericana');
      expect(read.isbn, '9780306406157');
      expect(read.contributors.map((c) => c.name.family), [
        'García Márquez',
        'Rabassa',
      ]);
      expect(read.contributors.every((c) => c.personId != null), isTrue);
    });

    test('la misma persona en dos obras es UNA persona', () async {
      const saved = ReferenceData(contributors: [Contributor(name: garcia)]);
      await repository.saveReference('libro', saved);
      await repository.saveReference('otro', saved);

      final first = (await repository.read('libro')).contributors.single;
      final second = (await repository.read('otro')).contributors.single;

      expect(first.personId, isNotNull);
      expect(first.personId, second.personId);
    });

    test('guarda la referencia entera: lo que no trae se borra', () async {
      await repository.saveReference(
        'libro',
        const ReferenceData(type: ReferenceType.book, publisher: 'Editorial'),
      );
      await repository.saveReference(
        'libro',
        const ReferenceData(type: ReferenceType.book),
      );

      final read = await repository.read('libro');

      expect(read.publisher, isNull);
      expect(read.type, ReferenceType.book);
    });

    test('lo que no es una fuente o no existe no se guarda', () async {
      const reference = ReferenceData(type: ReferenceType.book);

      expect(await repository.saveReference('nota', reference), isFalse);
      expect(await repository.saveReference('fantasma', reference), isFalse);
    });
  });

  group('la fecha de publicación', () {
    Future<DateTime?> publishedAt(String id) async => (await (db.select(
      db.knowledgeSources,
    )..where((s) => s.itemId.equals(id))).getSingle()).publishedAt;

    test('se guarda y se borra', () async {
      final date = DateTime(1967, 6, 5);

      expect(await repository.savePublishedAt('libro', date), isTrue);
      expect(await publishedAt('libro'), date);

      expect(await repository.savePublishedAt('libro', null), isTrue);
      expect(await publishedAt('libro'), isNull);
    });

    test('la de otra obra no se toca', () async {
      await repository.savePublishedAt('libro', DateTime(1967));

      expect(await publishedAt('otro'), isNull);
    });

    test('lo que no existe no se guarda', () async {
      expect(
        await repository.savePublishedAt('fantasma', DateTime(1967)),
        isFalse,
      );
    });
  });

  group('mirar', () {
    test('emite lo que hay y vuelve a emitir cuando cambia', () async {
      final seen = <ReferenceData>[];
      final subscription = repository.watch('libro').listen(seen.add);
      addTearDown(subscription.cancel);
      await _settle();

      expect(seen, isNotEmpty);
      expect(seen.last.isEmpty, isTrue);

      await repository.saveReference(
        'libro',
        const ReferenceData(type: ReferenceType.book, publisher: 'Editorial'),
      );
      await _settle();

      expect(seen.last.publisher, 'Editorial');
    });

    test(
      'renombrar a un autor en el vocabulario se ve en la referencia',
      () async {
        await repository.saveReference(
          'libro',
          const ReferenceData(contributors: [Contributor(name: garcia)]),
        );
        final seen = <ReferenceData>[];
        final subscription = repository.watch('libro').listen(seen.add);
        addTearDown(subscription.cancel);
        await _settle();
        final personId = seen.last.contributors.single.personId!;

        await (db.update(
          db.propertyValues,
        )..where((v) => v.id.equals(personId))).write(
          const PropertyValuesCompanion(
            value: Value('García Márquez, Gabo'),
            nameGiven: Value('Gabo'),
          ),
        );
        await _settle();

        expect(seen.last.contributors.single.name.given, 'Gabo');
      },
    );

    test('una fuente sin nada guardado emite una referencia vacía', () async {
      final first = await repository.watch('otro').first;

      expect(first.isEmpty, isTrue);
    });
  });
}

/// Un turno del bucle de eventos para que lleguen los avisos de la base y las
/// lecturas que provocan.
Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

KnowledgeItem _item(String id, {SourceKind kind = SourceKind.webPage}) =>
    KnowledgeItem(
      id: id,
      title: 'Un libro',
      source: Source(
        id: 'src-$id',
        kind: kind,
        capturedAt: DateTime(2026, 9, 11, 10),
      ),
      processingState: ProcessingState.ready,
      createdAt: DateTime(2026, 9, 11, 10),
      updatedAt: DateTime(2026, 9, 11, 10),
    );
