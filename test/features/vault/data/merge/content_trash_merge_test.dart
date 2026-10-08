import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/trashed_content_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/content_trash/data/repositories/content_trash_repository_impl.dart';
import 'package:sinapsis/features/content_trash/domain/entities/trashed_content.dart';

import '../../../../support/in_memory_file_store.dart';
import '../../../../support/test_vault.dart';

class _MockTelemetry extends Mock implements TelemetryService {}

/// La papelera del contenido y la fusión de bóvedas (F30, decisión 68).
///
/// La papelera es de cada dispositivo —el archivo vive en su disco—: no viaja
/// al fusionar. Lo que cruza es la decisión, por la versión del campo
/// `originalBlobPath` y por lo que entra o no entra de texto. Una fusión
/// nunca borra un archivo ni un texto: lo que deja de usar va a la papelera.
void main() {
  late TestVault tel;
  late TestVault pc;

  setUp(() async {
    tel = await TestVault.create(deviceId: 'tel');
    pc = await TestVault.create(deviceId: 'pc');
  });

  tearDown(() async {
    await tel.dispose();
    await pc.dispose();
  });

  ContentTrashRepositoryImpl trashOf(
    TestVault vault, {
    InMemoryFileStore? files,
  }) => ContentTrashRepositoryImpl(
    database: vault.db,
    files: files ?? InMemoryFileStore(),
    telemetry: _MockTelemetry(),
    clock: () => vault.now,
  );

  Future<List<TrashedContentRow>> trashRows(TestVault vault) =>
      vault.db.select(vault.db.trashedContents).get();

  Future<KnowledgeSourceRow> sourceOf(TestVault vault, String id) =>
      (vault.db.select(
        vault.db.knowledgeSources,
      )..where((s) => s.itemId.equals(id))).getSingle();

  /// «libro» nace en tel con su archivo y su texto, y pc lo recibe.
  Future<void> shareBook() async {
    tel.at(1);
    await tel.saveSource('libro', text: 'Roma.', originalName: 'roma.pdf');
    pc.at(2);
    await pc.mergeFrom(tel);
    expect(pc.hasOriginal('originales/libro/roma.pdf'), isTrue);
  }

  group('«solo el texto»: el archivo soltado', () {
    test('la otra bóveda deja de apuntarle, y el archivo espera en su '
        'papelera sin borrarse del disco', () async {
      await shareBook();
      tel.at(10);
      await trashOf(tel).keepOnlyText('libro');
      pc.at(11);

      await pc.mergeFrom(tel);

      expect((await sourceOf(pc, 'libro')).originalBlobPath, isNull);
      final waiting = (await trashRows(pc)).single;
      expect(waiting.kind, TrashedContentKind.file);
      expect(waiting.relativePath, 'originales/libro/roma.pdf');
      expect(waiting.trashedAt, pc.now);
      // Una fusión no borra archivos.
      expect(pc.hasOriginal('originales/libro/roma.pdf'), isTrue);
      // El texto sigue en las dos.
      expect((await pc.renditionsOf('libro')).single.content, 'Roma.');
    });

    test('y se recupera desde ahí, como cualquier otro', () async {
      await shareBook();
      tel.at(10);
      await trashOf(tel).keepOnlyText('libro');
      pc.at(11);
      await pc.mergeFrom(tel);
      final waiting = (await trashRows(pc)).single;
      // El archivo de pc está en su disco; el almacén de la prueba lo ve.
      final store = InMemoryFileStore();
      await store.save(
        bytes: Uint8List.fromList([1, 2, 3]),
        suggestedName: 'roma.pdf',
        id: 'libro',
      );

      final outcome = await trashOf(pc, files: store).restore(waiting.id);

      expect(
        outcome.getOrElse((f) => fail('$f')),
        ContentRestoreOutcome.restored,
      );
      expect(
        (await sourceOf(pc, 'libro')).originalBlobPath,
        'originales/libro/roma.pdf',
      );
      expect(await trashRows(pc), isEmpty);
    });

    test('lo que la copia no cambió no va a ninguna papelera', () async {
      await shareBook();
      tel.at(10);
      await tel.saveSource(
        'libro',
        text: 'Roma.',
        originalName: 'roma.pdf',
        title: 'Otro título',
      );
      pc.at(11);

      await pc.mergeFrom(tel);

      expect(await trashRows(pc), isEmpty);
      expect(
        (await sourceOf(pc, 'libro')).originalBlobPath,
        'originales/libro/roma.pdf',
      );
    });
  });

  group('«solo el libro»: el texto soltado', () {
    test(
      'no vuelve con la fusión: la persona lo sacó de este elemento',
      () async {
        await shareBook();
        tel.at(10);
        await trashOf(tel).keepOnlyFile('libro');
        // pc subrayó ese texto mientras tanto.
        pc.at(11);
        await pc.addHighlight('subrayado-de-pc', 'libro');
        tel.at(12);

        final result = await tel.mergeFrom(pc);

        expect(result.renditionsAdded, 0);
        expect(await tel.renditionsOf('libro'), isEmpty);
        expect((await sourceOf(tel, 'libro')).onlyFile, isTrue);
        // Sus subrayados, que son de ese texto, tampoco entran sueltos.
        expect(await tel.db.select(tel.db.highlights).get(), isEmpty);
        expect(await trashRows(tel), hasLength(1));
      },
    );

    test(
      'vencida la papelera, el texto que la otra bóveda todavía tiene '
      'entra como un texto más, y el elemento deja de ser «solo el libro»',
      () async {
        await shareBook();
        tel.at(10);
        await trashOf(tel).keepOnlyFile('libro');
        tel.at(10 + 31 * 24 * 60);
        await trashOf(tel).purgeExpired();
        expect(await trashRows(tel), isEmpty);

        await tel.mergeFrom(pc);

        expect((await tel.renditionsOf('libro')).single.content, 'Roma.');
        expect((await sourceOf(tel, 'libro')).onlyFile, isFalse);
      },
    );

    test(
      'un elemento nuevo llega «solo el libro» si así estaba, sin texto',
      () async {
        await shareBook();
        pc.at(10);
        await trashOf(pc).keepOnlyFile('libro');
        final fresh = await TestVault.create(deviceId: 'otro');
        addTearDown(fresh.dispose);
        fresh.at(20);

        await fresh.mergeFrom(pc);

        expect(await fresh.renditionsOf('libro'), isEmpty);
        expect((await sourceOf(fresh, 'libro')).onlyFile, isTrue);
        // La papelera no viaja: el texto soltado queda en la de pc.
        expect(await trashRows(fresh), isEmpty);
        expect(await trashRows(pc), hasLength(1));
      },
    );
  });

  test('la papelera del contenido no viaja: ni la de la copia entra, ni la '
      'de acá sale', () async {
    await shareBook();
    tel.at(10);
    await trashOf(tel).keepOnlyText('libro');
    final before = await trashRows(tel);
    pc.at(11);

    await pc.mergeFrom(tel);
    await tel.mergeFrom(pc);

    // La de tel sigue como estaba; la de pc tiene solo lo que ella dejó de
    // usar, no una copia de la fila de tel.
    expect(await trashRows(tel), before);
    final ids = {for (final row in await trashRows(pc)) row.id};
    expect(ids.intersection({for (final row in before) row.id}), isEmpty);
  });

  test('un texto de la papelera guarda el contenido y los subrayados de '
      'la forma que se soltó', () async {
    tel.at(1);
    await tel.saveSource('libro', text: 'Roma.', originalName: 'roma.pdf');
    await tel.addHighlight('subrayado', 'libro');
    tel.at(5);

    final trashed = (await trashOf(
      tel,
    ).keepOnlyFile('libro')).getOrElse((_) => const <TrashedContent>[]);

    expect(trashed, hasLength(1));
    final row = (await trashRows(tel)).single;
    expect(row.content, 'Roma.');
    expect(row.highlights, contains('subrayado'));
  });
}
