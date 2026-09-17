import 'package:async/async.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/explorer/data/repositories/explorer_repository_impl.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Contra SQLite real, en memoria — igual que
/// `organize_repository_impl_test.dart`: lo que hay que verificar acá son
/// las restricciones del esquema (la unicidad del nombre por nivel, la
/// cascada de borrado hacia las subcarpetas), no algo que un doble pudiera
/// simular sin ejercitarlas de verdad.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl libraryRepository;
  late ExplorerRepositoryImpl repository;
  final now = DateTime(2026, 9, 17, 10);
  var counter = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    libraryRepository = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
    );
    repository = ExplorerRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      ids: FakeIdGenerator(),
      clock: () => now,
    );
    counter = 0;
  });

  tearDown(() => db.close());

  Future<KnowledgeItem> seedItem({String title = 'Un elemento'}) async {
    final n = counter++;
    final item = KnowledgeItem(
      id: 'item-$n',
      title: title,
      source: Source(
        id: 'src-$n',
        kind: SourceKind.webPage,
        capturedAt: now,
        url: 'https://ejemplo.org/$n',
      ),
      processingState: ProcessingState.ready,
      createdAt: now,
      updatedAt: now,
    );

    final result = await libraryRepository.save(item);
    return result.getRight().toNullable()!;
  }

  group('listar todas', () {
    test('ordenadas alfabéticamente, actualizándose solo', () async {
      final queue = StreamQueue(repository.watchAllFolders());

      expect(await queue.next, isEmpty);

      await repository.createFolder(name: 'Filosofía', parentId: null);
      expect((await queue.next).map((f) => f.name), ['Filosofía']);

      await repository.createFolder(name: 'Ciencia', parentId: null);
      expect((await queue.next).map((f) => f.name), ['Ciencia', 'Filosofía']);

      await queue.cancel();
    });
  });

  group('crear', () {
    test('un nombre nuevo en la raíz se crea', () async {
      final result = await repository.createFolder(
        name: 'Proyectos',
        parentId: null,
      );

      final folder = result.getRight().toNullable()!;
      expect(folder.name, 'Proyectos');
      expect(folder.parentId, isNull);
    });

    test('un nombre repetido en el mismo nivel, sin distinguir mayúsculas, '
        'falla', () async {
      await repository.createFolder(name: 'Proyectos', parentId: null);

      final result = await repository.createFolder(
        name: 'proyectos',
        parentId: null,
      );

      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    });

    test('el mismo nombre en niveles distintos no choca', () async {
      final parent = (await repository.createFolder(
        name: 'Filosofía',
        parentId: null,
      )).getRight().toNullable()!;
      // "Ética" en la raíz y "Ética" adentro de Filosofía son carpetas
      // distintas: el choque de nombres solo tiene sentido entre hermanas.
      await repository.createFolder(name: 'Ética', parentId: null);

      final result = await repository.createFolder(
        name: 'Ética',
        parentId: parent.id,
      );

      expect(result.isRight(), isTrue);
    });

    test('un nombre vacío falla', () async {
      final result = await repository.createFolder(name: '   ', parentId: null);

      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    });

    test('dentro de otra carpeta queda con ese padre', () async {
      final parent = (await repository.createFolder(
        name: 'Filosofía',
        parentId: null,
      )).getRight().toNullable()!;

      final result = await repository.createFolder(
        name: 'Ética',
        parentId: parent.id,
      );

      expect(result.getRight().toNullable()!.parentId, parent.id);
    });
  });

  group('renombrar', () {
    test('cambia el nombre', () async {
      final created = (await repository.createFolder(
        name: 'Viejo',
        parentId: null,
      )).getRight().toNullable()!;

      final result = await repository.renameFolder(
        id: created.id,
        name: 'Nuevo',
      );

      expect(result.getRight().toNullable()!.name, 'Nuevo');
    });

    test('a un nombre que ya usa una hermana falla', () async {
      await repository.createFolder(name: 'Uno', parentId: null);
      final dos = (await repository.createFolder(
        name: 'Dos',
        parentId: null,
      )).getRight().toNullable()!;

      final result = await repository.renameFolder(id: dos.id, name: 'uno');

      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    });

    test('a su propio nombre no falla por choque consigo misma', () async {
      final folder = (await repository.createFolder(
        name: 'Mismo',
        parentId: null,
      )).getRight().toNullable()!;

      final result = await repository.renameFolder(
        id: folder.id,
        name: 'Mismo',
      );

      expect(result.isRight(), isTrue);
    });
  });

  group('borrar', () {
    test('borra en cascada las subcarpetas', () async {
      final parent = (await repository.createFolder(
        name: 'Filosofía',
        parentId: null,
      )).getRight().toNullable()!;
      final child = (await repository.createFolder(
        name: 'Ética',
        parentId: parent.id,
      )).getRight().toNullable()!;

      await repository.deleteFolder(parent.id);

      final remaining = await repository.watchAllFolders().first;
      expect(remaining.map((f) => f.id), isNot(contains(child.id)));
    });

    test('el elemento que tenía adentro no se borra, solo deja de estar '
        'organizado ahí', () async {
      final folder = (await repository.createFolder(
        name: 'Efímera',
        parentId: null,
      )).getRight().toNullable()!;
      final item = await seedItem();
      await repository.addItemToFolder(itemId: item.id, folderId: folder.id);

      await repository.deleteFolder(folder.id);

      final reloaded = await libraryRepository.findById(item.id);
      expect(reloaded.isRight(), isTrue);
    });

    test('borrar una que no existe no falla', () async {
      final result = await repository.deleteFolder('no-existe');

      expect(result.isRight(), isTrue);
    });
  });

  group('qué hay en cada carpeta', () {
    test('un elemento recién guardado aparece sin carpeta', () async {
      final item = await seedItem();

      final unfiled = await repository.watchItemIdsInFolder(null).first;

      expect(unfiled, contains(item.id));
    });

    test('agregarlo a una carpeta lo saca de "sin carpeta"', () async {
      final folder = (await repository.createFolder(
        name: 'Trabajo',
        parentId: null,
      )).getRight().toNullable()!;
      final item = await seedItem();

      await repository.addItemToFolder(itemId: item.id, folderId: folder.id);

      final unfiled = await repository.watchItemIdsInFolder(null).first;
      final inFolder = await repository.watchItemIdsInFolder(folder.id).first;
      expect(unfiled, isNot(contains(item.id)));
      expect(inFolder, contains(item.id));
    });

    test('agregarlo a una segunda carpeta lo deja en las dos — copiar, no '
        'mover', () async {
      final a = (await repository.createFolder(
        name: 'A',
        parentId: null,
      )).getRight().toNullable()!;
      final b = (await repository.createFolder(
        name: 'B',
        parentId: null,
      )).getRight().toNullable()!;
      final item = await seedItem();

      await repository.addItemToFolder(itemId: item.id, folderId: a.id);
      await repository.addItemToFolder(itemId: item.id, folderId: b.id);

      final folders = await repository.watchFolderIdsForItem(item.id).first;
      expect(folders, {a.id, b.id});
    });

    test('agregarlo dos veces a la misma carpeta no falla', () async {
      final folder = (await repository.createFolder(
        name: 'Trabajo',
        parentId: null,
      )).getRight().toNullable()!;
      final item = await seedItem();

      await repository.addItemToFolder(itemId: item.id, folderId: folder.id);
      final result = await repository.addItemToFolder(
        itemId: item.id,
        folderId: folder.id,
      );

      expect(result.isRight(), isTrue);
    });

    test('quitarlo de una carpeta lo deja de nuevo sin carpeta si no estaba '
        'en ninguna otra', () async {
      final folder = (await repository.createFolder(
        name: 'Trabajo',
        parentId: null,
      )).getRight().toNullable()!;
      final item = await seedItem();
      await repository.addItemToFolder(itemId: item.id, folderId: folder.id);

      await repository.removeItemFromFolder(
        itemId: item.id,
        folderId: folder.id,
      );

      final unfiled = await repository.watchItemIdsInFolder(null).first;
      expect(unfiled, contains(item.id));
    });
  });
}
