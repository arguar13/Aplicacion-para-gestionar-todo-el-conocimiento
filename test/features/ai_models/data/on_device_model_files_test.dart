import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/network/in_app_model_file_transfer.dart';
import 'package:sinapsis/core/network/model_file_transfer.dart';
import 'package:sinapsis/features/ai_models/data/on_device/on_device_model_files.dart';
import 'package:sinapsis/features/ai_models/domain/entities/on_device_image_model.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';

import '../../../support/on_device_harness.dart';

const _sdxs = OnDeviceImageModel.sdxs;
const _turbo = OnDeviceImageModel.sdTurbo;

void main() {
  late Directory root;
  late OnDeviceFakes fakes;
  late OnDeviceModelFiles files;

  setUp(() {
    root = Directory.systemTemp.createTempSync('modelos_imagen_');
    fakes = OnDeviceFakes(root: root);
    files = fakes.files;
  });

  tearDown(() async {
    await files.dispose();
    root.deleteSync(recursive: true);
  });

  test('baja del commit fijado, avisa el avance y queda entero', () async {
    await files.prepare();
    final changes = <void>[];
    final sub = files.changes().listen(changes.add);
    addTearDown(sub.cancel);
    final progress = <double>[];
    final done = files.download(_sdxs).listen(progress.add).asFuture<void>();
    await pumpEventQueue();

    expect(fakes.transfer.urls.single, _sdxs.spec.downloadUrl);
    expect(fakes.transfer.labels.single, LongWorkDetail.imageModel);
    final bytes = fakeSpecOf(_sdxs).bytes;
    fakes.transfer.progress(_sdxs.spec.fileName, bytes ~/ 2);
    expect(await files.isDownloaded(_sdxs), isFalse);
    await fakes.transfer.finish(_sdxs.spec.fileName, fakeModelContent(_sdxs));
    await done;

    expect(progress.first, closeTo(0.5, 0.05));
    expect(progress.last, 1);
    expect(await files.isDownloaded(_sdxs), isTrue);
    expect(files.isDownloadedSync(_sdxs), isTrue);
    expect(files.isDownloadedSync(_turbo), isFalse);
    expect(fakes.fileOf(_sdxs).readAsStringSync(), fakeModelContent(_sdxs));
    expect(changes, hasLength(1));
  });

  test(
    'uno que llega distinto de la huella se descarta y la descarga falla',
    () async {
      final done = files.download(_sdxs).drain<void>();
      await pumpEventQueue();
      // Mismo tamaño, otro contenido.
      final wrong = 'x' * fakeSpecOf(_sdxs).bytes;
      await fakes.transfer.finish(_sdxs.spec.fileName, wrong);

      await expectLater(done, throwsA(isA<OnDeviceModelIntegrityException>()));
      expect(await files.isDownloaded(_sdxs), isFalse);
      expect(fakes.fileOf(_sdxs).existsSync(), isFalse);
    },
  );

  test('ya bajado: emite 1 y cierra sin tocar la red', () async {
    fakes.placeDownloaded(_turbo);
    expect(await files.download(_turbo).toList(), [1]);
    expect(fakes.transfer.urls, isEmpty);
  });

  test('sin lugar, lo dice la transferencia tal cual', () async {
    fakes.transfer.failWith = const InsufficientStorageException(
      requiredBytes: 10,
      availableBytes: 2,
    );
    await expectLater(
      files.download(_turbo).drain<void>(),
      throwsA(isA<InsufficientStorageException>()),
    );
  });

  test('pausar deja lo bajado; seguir retoma y cancelar lo borra', () async {
    final first = files.download(_turbo).drain<void>();
    await pumpEventQueue();
    expect(await files.isDownloading(_turbo), isTrue);
    fakes.transfer.progress(_turbo.spec.fileName, 6);
    await files.pause(_turbo);
    await expectLater(first, throwsA(isA<ModelDownloadPausedException>()));

    final paused = await files.pausedProgress(_turbo);
    expect(paused, closeTo(6 / fakeSpecOf(_turbo).bytes, 0.001));
    expect(await files.isDownloading(_turbo), isFalse);

    // Seguir: otra descarga del mismo archivo, que la transferencia retoma.
    final again = files.download(_turbo).drain<void>();
    await pumpEventQueue();
    await files.cancel(_turbo);
    await expectLater(again, throwsA(isA<ModelDownloadCancelledException>()));
    expect(await files.pausedProgress(_turbo), isNull);
  });

  test('borrar saca solo el archivo del modelo y lo que quedó a medias: nada '
      'más de la app', () async {
    fakes
      ..placeDownloaded(_sdxs)
      ..placeDownloaded(_turbo);
    final target = fakes.fileOf(_sdxs);
    final partial = InAppModelFileTransfer.partialOf(target)
      ..writeAsStringSync('a medias');
    // Lo de otros modelos y de la app, al lado.
    final whisper = File(
      '${root.path}/modelos/whisper-small-atencion/small-tokens.txt',
    )..createSync(recursive: true);
    final vault = File('${root.path}/boveda.sqlite')..writeAsStringSync('base');

    await files.prepare();
    await files.delete(_sdxs);

    expect(target.existsSync(), isFalse);
    expect(partial.existsSync(), isFalse);
    expect(files.isDownloadedSync(_sdxs), isFalse);
    expect(files.isDownloadedSync(_turbo), isTrue);
    expect(whisper.existsSync(), isTrue);
    expect(vault.readAsStringSync(), 'base');
  });

  test('uno con otro tamaño no cuenta como bajado', () async {
    final file = fakes.fileOf(_sdxs)
      ..createSync(recursive: true)
      ..writeAsStringSync('cortado');
    await files.prepare();
    expect(file.existsSync(), isTrue);
    expect(await files.isDownloaded(_sdxs), isFalse);
    expect(files.isDownloadedSync(_sdxs), isFalse);
  });

  test('sin resolver la carpeta, isDownloadedSync dice que no', () {
    fakes.placeDownloaded(_sdxs);
    expect(files.isDownloadedSync(_sdxs), isFalse);
  });
}
