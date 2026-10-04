import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/network/model_file_transfer.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';
import 'package:sinapsis/features/transform/presentation/providers/model_download_notifier.dart';

/// Lo que se le pidió al servicio en primer plano.
class _RecordingKeeper implements LongWorkKeeper {
  final calls = <String>[];

  @override
  void working({
    required int done,
    required int total,
    LongWorkKind kind = LongWorkKind.dataSync,
    String? detail,
  }) => calls.add('$done/$total $detail ${kind.name}');

  @override
  void idle() => calls.add('suelta');
}

void main() {
  late _RecordingKeeper keeper;
  late int finished;
  late ModelDownloadNotifier notifier;
  late List<StreamController<double>> downloads;

  Stream<double> download() {
    final controller = StreamController<double>();
    downloads.add(controller);
    return controller.stream;
  }

  setUp(() {
    keeper = _RecordingKeeper();
    finished = 0;
    downloads = [];
    notifier = ModelDownloadNotifier(
      keeper: () => keeper,
      detail: LongWorkDetail.languageModel,
      onFinished: () => finished++,
    );
  });

  tearDown(() {
    if (notifier.mounted) notifier.dispose();
  });

  test('una sola descarga por modelo: pedir otra con una en curso no '
      'arranca nada', () async {
    expect(notifier.start(download), isTrue);
    expect(notifier.start(download), isFalse);

    expect(downloads, hasLength(1));
    expect(notifier.state, isA<ModelDownloadRunning>());
  });

  test('mientras baja, mantiene viva la app y dice qué modelo y cuánto '
      'va', () async {
    notifier.start(download);
    downloads.single.add(0.47);
    await pumpEventQueue();

    expect(
      notifier.state,
      isA<ModelDownloadRunning>().having((s) => s.progress, 'avance', 0.47),
    );
    expect(keeper.calls, [
      '0/1000 language_model dataSync',
      '470/1000 language_model dataSync',
    ]);
  });

  test('al terminar suelta el servicio, vuelve a quieto y avisa a quien '
      'esperaba el modelo', () async {
    notifier.start(download);
    await downloads.single.close();
    await pumpEventQueue();

    expect(notifier.state, isA<ModelDownloadIdle>());
    expect(keeper.calls.last, 'suelta');
    expect(finished, 1);
  });

  test('un error queda como error aunque el stream se cierre después, y no '
      'avisa que terminó', () async {
    notifier.start(download);
    downloads.single.addError(StateError('sin red'));
    await downloads.single.close();
    await pumpEventQueue();

    expect(
      notifier.state,
      isA<ModelDownloadFailed>().having(
        (s) => s.error,
        'error',
        isA<StateError>(),
      ),
    );
    expect(keeper.calls.last, 'suelta');
    expect(finished, 0);
  });

  test('después de un error se puede volver a intentar', () async {
    notifier.start(download);
    downloads.single.addError(StateError('sin red'));
    await pumpEventQueue();

    expect(notifier.start(download), isTrue);
    expect(downloads, hasLength(2));
  });

  test('olvidar el error no toca una descarga en curso', () async {
    notifier
      ..start(download)
      ..clearError();

    expect(notifier.state, isA<ModelDownloadRunning>());
  });

  test('descartado a mitad de una descarga, suelta el servicio', () async {
    notifier
      ..start(download)
      ..dispose();

    expect(keeper.calls.last, 'suelta');
  });

  test('si la baja el gestor del sistema, no pide el servicio: baja en su '
      'propio proceso, con su notificación (F29)', () async {
    final system = ModelDownloadNotifier(
      keeper: null,
      detail: LongWorkDetail.languageModel,
    );
    addTearDown(system.dispose);

    system.start(download);
    downloads.single.add(0.5);
    await downloads.single.close();
    await pumpEventQueue();

    expect(keeper.calls, isEmpty);
    expect(system.state, isA<ModelDownloadIdle>());
  });

  group('al abrir la app (F29)', () {
    test('se engancha a la descarga que siguió con la app cerrada y muestra '
        'cuánto va', () async {
      final resumed = await notifier.resume(
        isDownloading: () async => true,
        download: download,
      );
      downloads.single.add(0.8);
      await pumpEventQueue();

      expect(resumed, isTrue);
      expect(
        notifier.state,
        isA<ModelDownloadRunning>().having((s) => s.progress, 'avance', 0.8),
      );
    });

    test('si terminó con la app cerrada, al recogerla avisa a quien esperaba '
        'el modelo', () async {
      await notifier.resume(
        isDownloading: () async => true,
        download: download,
      );
      await downloads.single.close();
      await pumpEventQueue();

      expect(notifier.state, isA<ModelDownloadIdle>());
      expect(finished, 1);
    });

    test('si falló con la app cerrada, se ve el error', () async {
      await notifier.resume(
        isDownloading: () async => true,
        download: download,
      );
      downloads.single.addError(StateError('sin red'));
      await pumpEventQueue();

      expect(notifier.state, isA<ModelDownloadFailed>());
    });

    test(
      'sin descarga en curso no baja nada: nada se baja sin pedirlo',
      () async {
        final resumed = await notifier.resume(
          isDownloading: () async => false,
          download: download,
        );

        expect(resumed, isFalse);
        expect(downloads, isEmpty);
        expect(notifier.state, isA<ModelDownloadIdle>());
      },
    );

    test(
      'con una descarga ya seguida en esta sesión, no arranca otra',
      () async {
        notifier.start(download);

        final resumed = await notifier.resume(
          isDownloading: () async => true,
          download: download,
        );

        expect(resumed, isFalse);
        expect(downloads, hasLength(1));
      },
    );
  });

  group('cancelar', () {
    test('corta la descarga, suelta el servicio y queda como si nunca hubiera '
        'empezado', () async {
      var cancelled = 0;
      notifier.start(download);

      await notifier.cancel(() async => cancelled++);

      expect(cancelled, 1);
      expect(downloads.single.hasListener, isFalse);
      expect(keeper.calls.last, 'suelta');
      expect(notifier.state, isA<ModelDownloadIdle>());
      expect(finished, 0);
    });

    test('sin descarga en curso no hace nada', () async {
      var cancelled = 0;

      await notifier.cancel(() async => cancelled++);

      expect(cancelled, 0);
    });

    test('cancelada desde otro lado, no queda como error', () async {
      notifier.start(download);
      downloads.single.addError(const ModelDownloadCancelledException());
      await pumpEventQueue();

      expect(notifier.state, isA<ModelDownloadIdle>());
    });
  });
}
