import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/network/model_file_transfer.dart';
import 'package:sinapsis/features/narration/data/voices/offline_voice_files.dart';
import 'package:sinapsis/features/narration/data/voices/voice_package_unpacker.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';

import '../../../../support/on_device_harness.dart';
import '../../../../support/voice_package_fixture.dart';

/// Un abridor que falla como el disco lleno, a mitad de un archivo.
class _DiskFullUnpacker implements VoicePackageUnpacker {
  @override
  Future<void> unpack(File archive, Directory into) async {
    into.createSync(recursive: true);
    File(p.join(into.path, 'a medias.onnx')).writeAsStringSync('mod');
    throw const FileSystemException(
      'No space left on device',
      'a medias.onnx',
      OSError('No space left on device', 28),
    );
  }
}

void main() {
  late Directory root;
  late FakeModelTransfer transfer;
  late OfflineVoiceFiles files;

  setUp(() {
    root = Directory.systemTemp.createTempSync('voces-');
    addTearDown(() => root.deleteSync(recursive: true));
    transfer = FakeModelTransfer();
    files = OfflineVoiceFiles(
      transfer: transfer,
      rootDirectory: () async => root,
    );
    addTearDown(files.dispose);
  });

  String voicesDir() => p.join(root.path, 'modelos', 'voces');

  /// Baja [fixture] hasta el final, y espera a que quede abierta.
  Future<List<double>> install(VoicePackageFixture fixture) async {
    final progress = <double>[];
    final done = Completer<void>();
    // Un error y después el cierre: el primero es el que cuenta.
    files
        .download(fixture.package)
        .listen(
          progress.add,
          cancelOnError: true,
          onError: done.completeError,
          onDone: done.complete,
        );
    await pumpEventQueue();
    transfer.progress(fixture.package.archiveName, fixture.package.bytes ~/ 2);
    await transfer.finishBytes(fixture.package.archiveName, fixture.bytes);
    await done.future;
    return progress;
  }

  group('las voces sin conexión en el teléfono (F47, paso 3)', () {
    test('nada se baja sin pedirlo: crear el gestor y preguntar no toca la '
        'red', () async {
      final fixture = VoicePackageFixture.piper();
      expect(await files.isInstalled(fixture.package), isFalse);
      expect(await files.isDownloading(fixture.package), isFalse);
      expect(await files.installedPackageIds(), isEmpty);
      expect(transfer.urls, isEmpty);
    });

    test('bajar trae el paquete de sherpa-onnx, lo abre, deja su ficha y '
        'borra el comprimido', () async {
      final fixture = VoicePackageFixture.piper();
      final changes = <void>[];
      files.changes().listen(changes.add);

      final progress = await install(fixture);

      expect(transfer.urls, [fixture.package.url]);
      expect(transfer.labels, [LongWorkDetail.voiceModel]);
      expect(progress.first, closeTo(0.45, 0.01));
      expect(
        progress,
        containsAllInOrder([OfflineVoiceFiles.downloadShare, 1]),
      );
      expect(await files.isInstalled(fixture.package), isTrue);
      expect(await files.installedPackageIds([fixture.package]), {
        fixture.package.id,
      });
      expect(changes, hasLength(1));
      // Queda solo la voz abierta: ni el comprimido ni la carpeta de abrir.
      expect(Directory(voicesDir()).listSync().map((e) => p.basename(e.path)), [
        fixture.package.id,
      ]);
      expect(await files.installedBytes(fixture.package), greaterThan(0));
    });

    test('la voz dice dónde están sus archivos, sin suponer el nombre del '
        'modelo', () async {
      final fixture = VoicePackageFixture.piper();
      await install(fixture);
      final voice = OfflineVoice(
        package: fixture.package,
        speakerId: 0,
        name: 'Prueba',
        locale: 'xx-XX',
      );

      final config = (await files.engineConfigOf(voice))!;
      final base = p.join(
        voicesDir(),
        fixture.package.id,
        'vits-piper-xx_XX-prueba-medium',
      );
      expect(config.family, OfflineVoiceFamily.piper);
      expect(config.model, p.join(base, 'xx_XX-prueba-medium.onnx'));
      expect(config.tokens, p.join(base, 'tokens.txt'));
      expect(config.dataDir, p.join(base, 'espeak-ng-data'));
      expect(config.voices, isNull);
      expect(File(config.model).readAsStringSync(), 'modelo');
    });

    test('Kokoro, con sus estilos y su forma de pronunciar', () async {
      final fixture = VoicePackageFixture.piper(
        id: 'kokoro-prueba',
        folder: 'kokoro-prueba',
        family: OfflineVoiceFamily.kokoro,
      );
      await install(fixture);
      final voice = OfflineVoice(
        package: fixture.package,
        speakerId: 28,
        name: 'Dora',
        locale: 'es',
        kokoroPhonemes: const KokoroPhonemes.espeak('es'),
      );

      final config = (await files.engineConfigOf(voice))!;
      expect(config.voices, endsWith('voices.bin'));
      expect(config.espeakVoice, 'es');
      expect(config.lexicon, isNull);
    });

    test('un paquete que llega distinto no se usa', () async {
      final fixture = VoicePackageFixture.piper();
      final errors = <Object>[];
      final done = Completer<void>();
      files
          .download(fixture.package)
          .listen((_) {}, onError: errors.add, onDone: done.complete);
      await pumpEventQueue();
      final tampered = [...fixture.bytes]..[20] ^= 0xFF;
      await transfer.finishBytes(fixture.package.archiveName, tampered);
      await done.future;

      expect(errors.single, isA<OfflineVoiceIntegrityException>());
      expect(await files.isInstalled(fixture.package), isFalse);
    });

    test('un paquete sin modelo no se da por bueno, y no queda nada', () async {
      final fixture = VoicePackageFixture.piper(
        files: {'tokens.txt': 'a 1', 'espeak-ng-data/phontab': 'f'},
      );
      await expectLater(
        install(fixture),
        throwsA(isA<OfflineVoicePackageException>()),
      );

      expect(await files.isInstalled(fixture.package), isFalse);
      // Ni lo abierto a medias ni el comprimido, que no sirve.
      expect(Directory(voicesDir()).listSync(), isEmpty);
    });

    test('sin lugar al abrirlo, lo dice, borra lo abierto a medias y guarda '
        'el comprimido', () async {
      files = OfflineVoiceFiles(
        transfer: transfer,
        rootDirectory: () async => root,
        unpacker: _DiskFullUnpacker(),
      );
      final fixture = VoicePackageFixture.piper();

      await expectLater(
        install(fixture),
        throwsA(isA<InsufficientStorageException>()),
      );
      expect(Directory(voicesDir()).listSync().map((e) => p.basename(e.path)), [
        fixture.package.archiveName,
      ]);
    });

    test(
      'un comprimido que quedó entero se abre sin volver a bajarlo',
      () async {
        final fixture = VoicePackageFixture.piper();
        Directory(voicesDir()).createSync(recursive: true);
        File(
          p.join(voicesDir(), fixture.package.archiveName),
        ).writeAsBytesSync(fixture.bytes);

        await files.download(fixture.package).drain<void>();

        expect(transfer.urls, isEmpty);
        expect(await files.isInstalled(fixture.package), isTrue);
      },
    );

    test('una que ya está no vuelve a bajarse', () async {
      final fixture = VoicePackageFixture.piper();
      await install(fixture);

      final progress = await files.download(fixture.package).toList();

      expect(progress, [1]);
      expect(transfer.urls, hasLength(1));
    });

    test('borrarla deja el lugar como estaba', () async {
      final fixture = VoicePackageFixture.piper();
      await install(fixture);

      await files.delete(fixture.package);

      expect(await files.isInstalled(fixture.package), isFalse);
      expect(Directory(voicesDir()).listSync(), isEmpty);
    });

    test('pausar y cancelar van a la transferencia', () async {
      final fixture = VoicePackageFixture.piper();
      final errors = <Object>[];
      files.download(fixture.package).listen((_) {}, onError: errors.add);
      await pumpEventQueue();
      expect(await files.isDownloading(fixture.package), isTrue);

      await files.pause(fixture.package);
      await pumpEventQueue();
      expect(errors.single, isA<ModelDownloadPausedException>());

      await files.cancel(fixture.package);
      expect(await files.isDownloading(fixture.package), isFalse);
    });
  });

  group('abrir un paquete (F47, paso 3)', () {
    test('no escribe afuera de su carpeta', () async {
      final fixture = VoicePackageFixture.piper(
        folder: '..',
        files: {'afuera.txt': 'no'},
      );
      final archive = File(p.join(root.path, 'paquete.tar.bz2'))
        ..writeAsBytesSync(fixture.bytes);
      final into = Directory(p.join(root.path, 'adentro'));

      await const IsolateVoicePackageUnpacker().unpack(archive, into);

      expect(File(p.join(root.path, 'afuera.txt')).existsSync(), isFalse);
      expect(into.listSync(), isEmpty);
    });
  });
}
