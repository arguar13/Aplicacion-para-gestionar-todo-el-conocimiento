import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
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
}
