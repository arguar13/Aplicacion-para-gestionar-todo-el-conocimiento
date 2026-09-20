import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/vault/data/services/backup_layout.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_preview.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_service.dart';

import '../../../../support/test_vault.dart';

/// La vista previa en seco de una fusión (F11): qué traería una copia de otra
/// bóveda, contado en SQL contra la de acá, sin escribir nada.
///
/// Son dos bóvedas de verdad —«tel», la de acá, y «pc», la que llega—, cada una
/// con su base y su carpeta de documentos, y un `.zip` armado por la app entre
/// las dos.
void main() {
  late TestVault local;
  late TestVault other;

  setUp(() async {
    local = await TestVault.create(deviceId: 'tel');
    other = await TestVault.create(deviceId: 'pc');
  });

  tearDown(() async {
    await local.dispose();
    await other.dispose();
  });

  /// Lo que traería la copia de [from] a la bóveda de acá.
  Future<VaultMergePreview> previewOf(TestVault from) async =>
      local.backup.previewMerge(await from.zip());

  group('los elementos', () {
    test('dos bóvedas vacías no tienen nada nuevo', () async {
      final preview = await previewOf(other);

      expect(preview.incomingItems, 0);
      expect(preview.hasNothingNew, isTrue);
    });

    test(
      'los que esta bóveda no tiene son nuevos, cada uno por su tipo',
      () async {
        await other.saveSource('a');
        await other.saveSource('b');
        await other.saveNote('n');

        final preview = await previewOf(other);

        expect(preview.incomingItems, 3);
        expect(preview.newSources, 2);
        expect(preview.newNotes, 1);
        expect(preview.newItems, 3);
        expect(preview.commonItems, 0);
        expect(preview.hasNothingNew, isFalse);
      },
    );

    test(
      'el mismo id es el mismo elemento aunque se editara en cada lado',
      () async {
        await local.saveSource(
          'a',
          title: 'Título de acá',
          text: 'Texto de acá.',
        );
        await other.saveSource(
          'a',
          title: 'Título de allá',
          text: 'Texto de allá.',
        );
        await other.saveSource('b');

        final preview = await previewOf(other);

        expect(preview.incomingItems, 2);
        expect(preview.commonItems, 1);
        expect(preview.newSources, 1);
        expect(preview.newNotes, 0);
      },
    );

    test('la copia de la misma bóveda no trae nada nuevo', () async {
      await local.saveSource('a');
      await local.saveNote('n');
      await local.addRelation('r', 'n', 'a');

      final preview = await previewOf(local);

      expect(preview.incomingItems, 2);
      expect(preview.commonItems, 2);
      expect(preview.newItems, 0);
      expect(preview.newRelations, 0);
      expect(preview.hasNothingNew, isTrue);
    });

    test(
      'lo que está en la papelera de la copia viaja: es un elemento',
      () async {
        await other.saveSource('a');
        await other.library.delete('a');

        final preview = await previewOf(other);

        expect(preview.newSources, 1);
      },
    );

    test('lo que está en la papelera de acá no vuelve a ser nuevo', () async {
      await local.saveSource('a');
      await local.library.delete('a');
      await other.saveSource('a');

      final preview = await previewOf(other);

      expect(preview.commonItems, 1);
      expect(preview.newItems, 0);
    });
  });

  group('lo que cuelga de los elementos', () {
    setUp(() async {
      for (final vault in [local, other]) {
        await vault.saveSource('a');
        await vault.saveSource('b');
      }
    });

    test(
      'un vínculo es el mismo por su id o por unir lo mismo con el mismo tipo',
      () async {
        // Los dos lados: a → b «cita», con ids distintos porque cada bóveda lo
        // creó por su cuenta.
        await local.addRelation('r-tel', 'a', 'b');
        await other.addRelation('r-pc', 'a', 'b');
        // Nuevos de verdad: otro sentido y otro tipo.
        await other.addRelation('r-inverso', 'b', 'a');
        await other.addRelation(
          'r-otro-tipo',
          'a',
          'b',
          kind: RelationKind.continues,
        );

        final preview = await previewOf(other);

        expect(preview.newRelations, 2);
      },
    );

    test('un vínculo con el mismo id que el de acá no es nuevo', () async {
      await local.addRelation('r', 'a', 'b');
      await other.addRelation('r', 'a', 'b');

      expect((await previewOf(other)).newRelations, 0);
    });

    test('los resaltados se cuentan por su id', () async {
      await local.addHighlight('hl-1', 'a');
      await other.addHighlight('hl-1', 'a');
      await other.addHighlight('hl-2', 'a', start: 6, end: 9);
      await other.addHighlight('hl-3', 'b');

      expect((await previewOf(other)).newHighlights, 2);
    });

    test('las tarjetas se cuentan por su id', () async {
      await local.addFlashcard('fc-1', 'a');
      await other.addFlashcard('fc-1', 'a');
      await other.addFlashcard('fc-2', 'a', front: '¿Otra?');

      expect((await previewOf(other)).newFlashcards, 1);
    });
  });

  group('los espacios', () {
    test(
      'uno es el mismo por su id o por su nombre, sin distinguir mayúsculas',
      () async {
        await local.addSpace('s1', 'Historia');
        await other.addSpace('s1', 'Otro nombre'); // mismo id
        await other.addSpace('s2', 'HISTORIA'); // mismo nombre
        await other.addSpace('s3', 'Física'); // nuevo

        expect((await previewOf(other)).newSpaces, 1);
      },
    );
  });

  group('los archivos originales', () {
    test('cuenta los que esta bóveda no tiene, con lo que pesan', () async {
      await other.saveSource(
        'a',
        originalName: 'informe.pdf',
        originalContent: 'x' * 100,
      );
      await other.saveSource(
        'b',
        originalName: 'audio.mp3',
        originalContent: 'y' * 40,
      );

      final preview = await previewOf(other);

      expect(preview.newFiles, 2);
      expect(preview.newFilesBytes, 140);
      expect(preview.filesMissingInBackup, 0);
    });

    test(
      'los que ya están en la carpeta de documentos de acá no cuentan',
      () async {
        await other.saveSource(
          'a',
          originalName: 'informe.pdf',
          originalContent: 'x' * 100,
        );
        await other.saveSource(
          'b',
          originalName: 'audio.mp3',
          originalContent: 'y' * 40,
        );
        await local.writeOriginal('originales/b/audio.mp3', 'y' * 40);

        final preview = await previewOf(other);

        expect(preview.newFiles, 1);
        expect(preview.newFilesBytes, 100);
      },
    );

    test('distingue los que la copia dice tener y no trae', () async {
      await other.saveSource('a', originalName: 'informe.pdf');
      await other.saveSource('c', originalName: 'perdido.txt');
      // El archivo se perdió en la bóveda de allá antes de armar la copia.
      File(
        p.join(other.docs.path, 'originales', 'c', 'perdido.txt'),
      ).deleteSync();

      final preview = await previewOf(other);

      expect(preview.newFiles, 1);
      expect(preview.filesMissingInBackup, 1);
    });

    test(
      'un archivo de la copia que ningún elemento usa no se cuenta',
      () async {
        final zip = zipOf({
          ...await _entriesOf(await other.zip()),
          '$kBackupOriginalsFolder/huerfano/suelto.bin': Uint8List.fromList([
            1,
            2,
            3,
          ]),
        });

        final preview = await local.backup.previewMerge(zip);

        expect(preview.newFiles, 0);
      },
    );
  });

  group('una copia de otra versión', () {
    test('una de una versión vieja se lee igual, ya puesta al día', () async {
      final preview = await local.backup.previewMerge(
        await vaultCopyAtV19(sourceId: 'vieja'),
      );

      expect(preview.incomingItems, 1);
      expect(preview.newSources, 1);
    });

    test('una de una versión más nueva se rechaza con su motivo', () async {
      final zip = zipOf({
        kBackupDatabaseEntryName: await sqliteBytesAtVersion(99),
      });

      await expectLater(
        local.backup.previewMerge(zip),
        throwsA(isA<VaultBackupTooNewException>()),
      );
    });

    test('lo que no es una copia se rechaza', () async {
      await expectLater(
        local.backup.previewMerge(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<InvalidVaultBackupException>()),
      );
    });
  });

  group('es una vista previa: no toca nada', () {
    Future<List<String>> attachedSchemas() async => [
      for (final row
          in await local.db.customSelect('PRAGMA database_list').get())
        row.read<String>('name'),
    ];

    test('no escribe ninguna fila en esta bóveda', () async {
      await local.saveSource('a');
      await other.saveSource('a');
      await other.saveSource('b', originalName: 'x.pdf');
      await other.saveNote('n');
      await other.addFlashcard('fc', 'a');
      final before = await local.counts();

      await previewOf(other);

      expect(await local.counts(), before);
      expect(local.hasOriginal('originales/b/x.pdf'), isFalse);
    });

    test('suelta la copia de la conexión al terminar', () async {
      await other.saveSource('a');

      await previewOf(other);

      expect(await attachedSchemas(), ['main']);
    });

    test('se puede repetir: da lo mismo y no se acumula nada', () async {
      await other.saveSource('a');
      await other.saveNote('n');
      final zip = await other.zip();

      final first = await local.backup.previewMerge(zip);
      final second = await local.backup.previewMerge(zip);

      expect(second, first);
      expect(await attachedSchemas(), ['main']);
    });

    test(
      'si la lectura falla, tampoco deja nada adjunto ni el temporal',
      () async {
        // Una base con la versión de esta app pero sin sus tablas: se abre y la
        // consulta falla a la mitad.
        final broken = zipOf({
          kBackupDatabaseEntryName: await sqliteBytesAtVersion(
            AppDatabase.currentSchemaVersion,
          ),
        });
        final tempRoot = await Directory.systemTemp.createTemp(
          'sinapsis_reader_',
        );
        addTearDown(() => tempRoot.delete(recursive: true));

        await IOOverrides.runZoned(
          () => expectLater(
            local.backup.previewMerge(broken),
            throwsA(isA<Object>()),
          ),
          getSystemTempDirectory: () => tempRoot,
        );

        expect(await attachedSchemas(), ['main']);
        expect(tempRoot.listSync(), isEmpty);
      },
    );

    test('tampoco deja el temporal cuando sale bien', () async {
      await other.saveSource('a');
      final zip = await other.zip();
      final tempRoot = await Directory.systemTemp.createTemp(
        'sinapsis_reader_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));

      await IOOverrides.runZoned(
        () => local.backup.previewMerge(zip),
        getSystemTempDirectory: () => tempRoot,
      );

      expect(tempRoot.listSync(), isEmpty);
    });
  });
}

/// Las entradas de un `.zip`, nombre → bytes, para armar una variante.
Future<Map<String, List<int>>> _entriesOf(Uint8List zip) async {
  final archive = ZipDecoder().decodeBytes(zip);
  return {
    for (final file in archive.files)
      if (file.isFile) file.name: file.content as List<int>,
  };
}
