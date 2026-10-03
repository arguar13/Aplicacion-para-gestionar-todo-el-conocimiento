import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';
import 'package:sinapsis/features/transform/domain/usecases/download_youtube_audio_usecase.dart';
import 'package:sinapsis/features/transform/presentation/providers/youtube_audio_download.dart';

import '../../../../support/sample_knowledge_item.dart';

/// La bajada del audio de YouTube de mentira: avanza y termina a pedido.
class _FakeDownload implements DownloadYouTubeAudioUseCase {
  final _done = Completer<KnowledgeItem>();
  void Function(int received, int? total)? _onProgress;

  void progress(int received, int total) => _onProgress?.call(received, total);

  void finish() => _done.complete(sampleKnowledgeItem());

  void fail() => _done.completeError(StateError('sin red'));

  @override
  Future<KnowledgeItem> call(
    String itemId, {
    void Function(int received, int? total)? onProgress,
    CancellationSignal? cancellation,
  }) {
    _onProgress = onProgress;
    return _done.future;
  }
}

/// Lo que se le pidió al servicio en primer plano.
class _RecordingKeeper implements LongWorkKeeper {
  final calls = <String>[];

  @override
  void working({
    required int done,
    required int total,
    LongWorkKind kind = LongWorkKind.dataSync,
    String? detail,
  }) => calls.add('$done/$total ${kind.name}');

  @override
  void idle() => calls.add('suelta');
}

/// La bajada automática del audio de un video (F24) mantiene viva la app:
/// sin eso, minimizarla la congelaba a mitad.
void main() {
  late _FakeDownload download;
  late _RecordingKeeper keeper;
  late YouTubeAudioDownloadNotifier notifier;

  setUp(() {
    download = _FakeDownload();
    keeper = _RecordingKeeper();
    notifier = YouTubeAudioDownloadNotifier(
      itemId: 'video',
      download: () => download,
      keeper: () => keeper,
    );
  });

  tearDown(() {
    if (notifier.mounted) notifier.dispose();
  });

  test('mientras baja pide el servicio, con el avance, y al terminar lo '
      'suelta', () async {
    final running = notifier.start();
    download
      ..progress(470, 1000)
      ..finish();
    await running;

    expect(keeper.calls, ['0/0 dataSync', '470/1000 dataSync', 'suelta']);
  });

  test('si falla, también lo suelta', () async {
    final running = notifier.start();
    download.fail();
    await running;

    expect(keeper.calls.last, 'suelta');
    expect(notifier.state, isA<AudioDownloadFailed>());
  });

  test('descartado a mitad, lo suelta', () async {
    unawaited(notifier.start());
    notifier.dispose();

    expect(keeper.calls.last, 'suelta');
  });
}
