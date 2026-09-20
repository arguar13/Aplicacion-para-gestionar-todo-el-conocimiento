import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';

import '../../../../support/in_memory_file_store.dart';

class _MockTelemetryService extends Mock implements TelemetryService {}

/// Lo que guardar deja escrito sobre QUIÉN y CUÁNDO cambió cada cosa (F11): la
/// revisión, el dispositivo y la versión por campo, a través del repositorio
/// —que es por donde entra todo lo que el usuario y los procesos guardan—.
void main() {
  const me = 'telefono';

  late AppDatabase db;
  late LibraryRepositoryImpl repository;
  var clockNow = DateTime(2026, 9, 20, 9);

  final captured = DateTime(2026, 9, 11, 10);

  setUp(() {
    clockNow = DateTime(2026, 9, 20, 9);
    db = AppDatabase(NativeDatabase.memory(), deviceId: me);
    repository = LibraryRepositoryImpl(
      database: db,
      telemetry: _MockTelemetryService(),
      files: InMemoryFileStore(),
      clock: () => clockNow,
    );
  });

  tearDown(() => db.close());

  void tick() => clockNow = clockNow.add(const Duration(minutes: 5));

  Rendition text(String content, {String id = 'r-1', bool primary = true}) =>
      Rendition.text(
        id: id,
        itemId: 'art',
        kind: RenditionKind.plainText,
        content: content,
        isPrimary: primary,
        createdAt: captured,
      );

  Rendition file(String path, {String id = 'f-1'}) => Rendition.file(
    id: id,
    itemId: 'art',
    kind: RenditionKind.pdf,
    relativePath: path,
    isPrimary: false,
    createdAt: captured,
  );

  KnowledgeItem item({
    String title = 'La república romana',
    List<Rendition> renditions = const [],
  }) => KnowledgeItem(
    id: 'art',
    title: title,
    source: Source(
      id: 'src-art',
      kind: SourceKind.webPage,
      capturedAt: captured,
      url: 'https://ejemplo.org/roma',
    ),
    processingState: ProcessingState.ready,
    createdAt: captured,
    updatedAt: captured,
    renditions: renditions,
  );

  Future<KnowledgeEntryRow> entry() => (db.select(
    db.knowledgeEntries,
  )..where((e) => e.id.equals('art'))).getSingle();

  Future<Map<String, FieldVersionRow>> versions() async => {
    for (final row in await db.select(db.fieldVersions).get())
      row.fieldName: row,
  };

  Future<void> createSpace(String id) => db
      .into(db.spaces)
      .insert(SpacesCompanion.insert(id: id, name: id, createdAt: captured));

  group('guardar un elemento', () {
    test('queda firmado con el dispositivo de la base', () async {
      await repository.save(item());

      final row = await entry();

      expect(row.deviceId, me);
      expect(row.rev, 1);
    });

    test('cada forma nueva queda versionada por su id', () async {
      await repository.save(
        item(renditions: [text('El texto.'), file('a/b.pdf')]),
      );

      final fields = await versions();

      expect(
        fields.keys,
        containsAll([
          EntryField.title,
          EntryField.originUrl,
          EntryField.rendition('r-1'),
          EntryField.rendition('f-1'),
        ]),
      );
      // Es un guardado: la revisión no sube por cada forma.
      expect((await entry()).rev, 1);
    });

    test(
      'guardar lo mismo otra vez no cambia la revisión ni las versiones',
      () async {
        await repository.save(item(renditions: [text('El texto.')]));
        final before = await versions();
        tick();

        await repository.save(item(renditions: [text('El texto.')]));

        expect((await entry()).rev, 1);
        final after = await versions();
        expect(after.keys, before.keys);
        for (final field in before.keys) {
          expect(
            after[field]!.updatedAt,
            before[field]!.updatedAt,
            reason: field,
          );
        }
      },
    );

    test(
      'cambiar solo el texto de una forma versiona esa forma y nada más',
      () async {
        await repository.save(
          item(
            renditions: [
              text('Uno.'),
              text('Otro.', id: 'r-2', primary: false),
            ],
          ),
        );
        final created = clockNow;
        tick();

        await repository.save(
          item(
            renditions: [
              text('Uno, corregido.'),
              text('Otro.', id: 'r-2', primary: false),
            ],
          ),
        );

        expect((await entry()).rev, 2);
        final fields = await versions();
        expect(fields[EntryField.rendition('r-1')]!.updatedAt, clockNow);
        // La otra forma tiene el mismo texto de antes: no cambió.
        expect(fields[EntryField.rendition('r-2')]!.updatedAt, created);
        expect(fields[EntryField.title]!.updatedAt, created);
      },
    );

    test('cambiar la ruta de un archivo también versiona esa forma', () async {
      await repository.save(item(renditions: [file('a/b.pdf')]));
      tick();

      await repository.save(item(renditions: [file('a/c.pdf')]));

      expect(
        (await versions())[EntryField.rendition('f-1')]!.updatedAt,
        clockNow,
      );
    });

    test(
      'cambiar el título y un texto a la vez sube la revisión una vez',
      () async {
        await repository.save(item(renditions: [text('Uno.')]));
        tick();

        await repository.save(
          item(title: 'Roma', renditions: [text('Uno, corregido.')]),
        );

        expect((await entry()).rev, 2);
        final fields = await versions();
        expect(fields[EntryField.title]!.updatedAt, clockNow);
        expect(fields[EntryField.rendition('r-1')]!.updatedAt, clockNow);
      },
    );

    test('una forma que desaparece del elemento se borra de la base', () async {
      await repository.save(
        item(
          renditions: [
            text('Uno.'),
            text('Otro.', id: 'r-2', primary: false),
          ],
        ),
      );

      await repository.save(item(renditions: [text('Uno.')]));

      final left = await db.select(db.renditions).get();
      expect(left.map((r) => r.id), ['r-1']);
    });
  });

  group('mover de espacio', () {
    test('queda registrado y sube la revisión', () async {
      await createSpace('esp');
      await repository.save(item());
      tick();

      await repository.assignSpace(itemId: 'art', spaceId: 'esp');

      expect((await entry()).spaceId, 'esp');
      expect((await entry()).rev, 2);
      expect((await entry()).deviceId, me);
      expect((await versions())[EntryField.spaceId]!.updatedAt, clockNow);
    });

    test('mandarlo al espacio en el que ya está no cambia nada', () async {
      await createSpace('esp');
      await repository.save(item());
      await repository.assignSpace(itemId: 'art', spaceId: 'esp');
      tick();

      await repository.assignSpace(itemId: 'art', spaceId: 'esp');

      expect((await entry()).rev, 2);
    });

    test('varios a la vez: cada uno queda registrado', () async {
      await createSpace('esp');
      await repository.save(item());
      tick();

      await repository.assignSpaceMany(itemIds: ['art'], spaceId: 'esp');

      expect((await entry()).rev, 2);
      expect((await versions())[EntryField.spaceId]!.updatedAt, clockNow);
    });
  });
}
