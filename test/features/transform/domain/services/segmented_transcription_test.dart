import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';
import 'package:sinapsis/features/transform/domain/services/audio_transcriber.dart';
import 'package:sinapsis/features/transform/domain/transformers/transform_context.dart';

/// `runSegmentedTranscription`: lo que hace retomable y cortable una
/// transcripción de horas (F21), probado sin motor.
void main() {
  /// Un motor que transcribe cada tramo como "tramo N", y anota cuáles le
  /// pidieron.
  final requested = <List<int>>[];
  Stream<(int, String)> engine(List<int> pending) {
    requested.add(pending);
    return Stream.fromIterable([
      for (final segment in pending) (segment, 'tramo $segment'),
    ]);
  }

  setUp(requested.clear);

  test('transcribe todos los tramos, en orden, y avisa el avance', () async {
    final context = _RecordingContext();

    final text = await runSegmentedTranscription(
      segmentCount: 3,
      session: TranscriptionSession(context: context),
      transcribe: engine,
    );

    expect(text, 'tramo 0 tramo 1 tramo 2');
    expect(context.progress, [(0, 3), (1, 3), (2, 3), (3, 3)]);
  });

  test('guarda cada tramo apenas llega', () async {
    final saved = <int, String>{};

    await runSegmentedTranscription(
      segmentCount: 2,
      session: TranscriptionSession(
        saveSegment: (segment, text) async => saved[segment] = text,
      ),
      transcribe: engine,
    );

    expect(saved, {0: 'tramo 0', 1: 'tramo 1'});
  });

  test('retoma: lo ya transcrito no se repite, y el avance arranca de '
      'ahí', () async {
    final context = _RecordingContext();

    final text = await runSegmentedTranscription(
      segmentCount: 4,
      session: TranscriptionSession(
        context: context,
        loadSegments: () async => {0: 'de antes', 1: 'también'},
      ),
      transcribe: engine,
    );

    expect(requested, [
      [2, 3],
    ]);
    expect(context.progress.first, (2, 4));
    expect(text, 'de antes también tramo 2 tramo 3');
  });

  test('todo hecho: no se le pide nada al motor', () async {
    final text = await runSegmentedTranscription(
      segmentCount: 1,
      session: TranscriptionSession(loadSegments: () async => {0: 'listo'}),
      transcribe: engine,
    );

    expect(requested, isEmpty);
    expect(text, 'listo');
  });

  test('los tramos en silencio no dejan espacios de más', () async {
    final text = await runSegmentedTranscription(
      segmentCount: 3,
      session: TranscriptionSession(loadSegments: () async => {1: '  '}),
      transcribe: engine,
    );

    expect(text, 'tramo 0 tramo 2');
  });

  test('cancelar corta en el acto, aunque el motor siga en un tramo, y lo '
      'suelta', () async {
    final signal = CancellationSignal();
    final context = CancellableTransformContext(signal);
    var released = false;

    final transcription = runSegmentedTranscription(
      segmentCount: 3,
      session: TranscriptionSession(context: context),
      // Entrega el primero y se queda "trabajando" en el segundo.
      transcribe: (pending) {
        late final StreamController<(int, String)> controller;
        controller = StreamController<(int, String)>(
          onListen: () => controller.add((0, 'tramo 0')),
          onCancel: () => released = true,
        );
        return controller.stream;
      },
    );
    await Future<void>.delayed(Duration.zero);
    signal.cancel();

    await expectLater(
      transcription,
      throwsA(isA<ProcessingCancelledException>()),
    );
    expect(released, isTrue);
  });

  test('ya cancelado, ni empieza', () async {
    final signal = CancellationSignal()..cancel();

    await expectLater(
      runSegmentedTranscription(
        segmentCount: 2,
        session: TranscriptionSession(
          context: CancellableTransformContext(signal),
        ),
        transcribe: engine,
      ),
      throwsA(isA<ProcessingCancelledException>()),
    );
    expect(requested, isEmpty);
  });
}

/// Un contexto de cola que anota el avance.
class _RecordingContext implements TransformContext {
  final progress = <(int, int)>[];

  @override
  bool get isCancelled => false;

  @override
  Future<void> get whenCancelled => Completer<void>().future;

  @override
  void throwIfCancelled() {}

  @override
  Future<void> enterLongLane() async {}

  @override
  void reportProgress(int done, int total) => progress.add((done, total));
}
