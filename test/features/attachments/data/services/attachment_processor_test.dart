import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/attachment_download_status.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/network/public_network.dart';
import 'package:sinapsis/features/attachments/data/services/attachment_processor.dart';
import 'package:sinapsis/features/attachments/domain/entities/attachment.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';
import 'package:sinapsis/features/transform/domain/transformers/transformer.dart';

import '../../../../support/attachment_test_doubles.dart';
import '../../../../support/in_memory_file_store.dart';
import '../../../../support/silent_logger.dart';

/// Un contexto que anota el avance y si se pasó al carril largo.
class _RecordingContext implements TransformContext {
  final cancellation = CancellationSignal();
  bool inLongLane = false;
  final progress = <(int, int)>[];

  @override
  bool get isCancelled => cancellation.isCancelled;

  @override
  Future<void> get whenCancelled => cancellation.whenCancelled;

  @override
  void throwIfCancelled() => cancellation.throwIfCancelled();

  @override
  Future<void> enterLongLane() async => inLongLane = true;

  @override
  void reportProgress(int done, int total) => progress.add((done, total));
}

void main() {
  late InMemoryFileStore files;
  late FakeAttachmentRepository attachments;
  late FakeLinkedFileFetcher fetcher;
  late int cap;

  final item = KnowledgeItem(
    id: 'pagina',
    title: 'Roma',
    source: Source(
      id: 'src',
      kind: SourceKind.webPage,
      capturedAt: DateTime(2026, 10),
      url: 'https://x.org/roma',
    ),
    processingState: ProcessingState.ready,
    createdAt: DateTime(2026, 10),
    updatedAt: DateTime(2026, 10),
  );

  setUp(() {
    files = InMemoryFileStore();
    attachments = FakeAttachmentRepository();
    fetcher = FakeLinkedFileFetcher(files);
    cap = 1000;
  });

  AttachmentProcessor processor({bool withFetcher = true}) =>
      AttachmentProcessor(
        attachments: attachments,
        fetcher: withFetcher ? fetcher : null,
        maxBytesPerItem: () => cap,
        logger: const SilentLogger(),
      );

  Future<void> offer(List<(String, RenditionKind, int, String?)> files) =>
      attachments.plan(item.id, [
        for (final (url, kind, position, title) in files)
          AttachmentCandidate(
            url: Uri.parse(url),
            kind: kind,
            position: position,
            title: title,
          ),
      ]);

  Map<String, AttachmentDownloadStatus> statuses() => {
    for (final d in attachments.downloads) d.url.toString(): d.status,
  };

  test(
    'baja todo en el carril largo, al «Contenido», con lo que se sabe',
    () async {
      fetcher.served
        ..['https://x.org/foto.jpg'] = const FakeServedFile([
          1,
          2,
        ], contentType: 'image/jpeg')
        ..['https://x.org/doc_88.pdf'] = const FakeServedFile([
          1,
          2,
          3,
        ], contentType: 'application/pdf');
      await offer([
        (
          'https://x.org/foto.jpg',
          RenditionKind.image,
          0,
          'El Coliseo de noche',
        ),
        ('https://x.org/doc_88.pdf', RenditionKind.pdf, 1, 'Informe anual'),
      ]);
      final context = _RecordingContext();

      expect(await processor().hasWork(item.id), isTrue);
      await processor().transform(item, context: context);

      expect(context.inLongLane, isTrue);
      expect(statuses().values, everyElement(AttachmentDownloadStatus.done));
      final saved = await attachments.attachmentsOf(item.id);
      expect(saved.map((a) => a.relativePath), [
        'originales/src/contenido/foto.jpg',
        'originales/src/contenido/Informe anual.pdf',
      ]);
      final photo = saved.first;
      expect(photo.title, 'El Coliseo de noche');
      expect(photo.originUrl, 'https://x.org/foto.jpg');
      expect(photo.mimeType, 'image/jpeg');
      expect(photo.sizeBytes, 2);
      expect(photo.kind, RenditionKind.image);
      expect(context.progress.last, (2000, 2000));
    },
  );

  test('primero documentos, audios, fotos y videos; lo que no entra queda '
      'afuera, y entra lo más chico que sigue', () async {
    cap = 10;
    fetcher.served
      ..['https://x.org/v.mp4'] = const FakeServedFile([
        1,
        2,
      ], contentType: 'video/mp4')
      ..['https://x.org/f.jpg'] = FakeServedFile(
        List.filled(4, 0),
        contentType: 'image/jpeg',
      )
      ..['https://x.org/a.mp3'] = FakeServedFile(
        List.filled(4, 0),
        contentType: 'audio/mpeg',
      )
      ..['https://x.org/d.pdf'] = FakeServedFile(
        List.filled(4, 0),
        contentType: 'application/pdf',
      );
    // En la página, al revés de como se bajan.
    await offer([
      ('https://x.org/v.mp4', RenditionKind.video, 0, null),
      ('https://x.org/f.jpg', RenditionKind.image, 1, null),
      ('https://x.org/a.mp3', RenditionKind.audio, 2, null),
      ('https://x.org/d.pdf', RenditionKind.pdf, 3, null),
    ]);

    await processor().transform(item, context: _RecordingContext());

    expect(fetcher.requested.map((u) => u.path), [
      '/d.pdf',
      '/a.mp3',
      '/f.jpg',
      '/v.mp4',
    ]);
    expect(statuses(), {
      'https://x.org/d.pdf': AttachmentDownloadStatus.done,
      'https://x.org/a.mp3': AttachmentDownloadStatus.done,
      // 4 + 4 + 4 pasa de 10: la foto queda afuera…
      'https://x.org/f.jpg': AttachmentDownloadStatus.leftOut,
      // …pero el video de 2 entra en lo que queda.
      'https://x.org/v.mp4': AttachmentDownloadStatus.done,
    });
    expect(await attachments.totalBytes(item.id), 10);
  });

  test('«Bajar el resto» baja lo de afuera, sin tope', () async {
    cap = 2;
    fetcher.served['https://x.org/v.mp4'] = FakeServedFile(
      List.filled(5, 0),
      contentType: 'video/mp4',
    );
    await offer([('https://x.org/v.mp4', RenditionKind.video, 0, 'Charla')]);

    await processor().transform(item, context: _RecordingContext());
    expect(statuses().values.single, AttachmentDownloadStatus.leftOut);
    expect(attachments.downloads.single.expectedBytes, 5);
    expect(await processor().hasWork(item.id), isFalse);

    await attachments.requestRest(item.id);
    expect(await processor().hasWork(item.id), isTrue);
    await processor().transform(item, context: _RecordingContext());

    expect(statuses().values.single, AttachmentDownloadStatus.done);
    expect((await attachments.attachmentsOf(item.id)).single.sizeBytes, 5);
  });

  test('una página en vez de un archivo, la red local o un 404: fallido, '
      'y se sigue con los demás', () async {
    fetcher.served
      ..['https://x.org/no-es.pdf'] = const FakeServedFile([
        60,
        104,
      ], contentType: 'text/html')
      ..['https://x.org/interna.pdf'] = const FakeServedFile(
        [],
        error: PrivateNetworkException('192.168.0.1'),
      )
      ..['https://x.org/bien.pdf'] = const FakeServedFile([
        1,
      ], contentType: 'application/pdf');
    await offer([
      ('https://x.org/no-es.pdf', RenditionKind.pdf, 0, null),
      ('https://x.org/interna.pdf', RenditionKind.pdf, 1, null),
      ('https://x.org/no-existe.pdf', RenditionKind.pdf, 2, null),
      ('https://x.org/bien.pdf', RenditionKind.pdf, 3, null),
    ]);

    await processor().transform(item, context: _RecordingContext());

    expect(statuses(), {
      'https://x.org/no-es.pdf': AttachmentDownloadStatus.failed,
      'https://x.org/interna.pdf': AttachmentDownloadStatus.failed,
      'https://x.org/no-existe.pdf': AttachmentDownloadStatus.failed,
      'https://x.org/bien.pdf': AttachmentDownloadStatus.done,
    });
    expect(files.paths, ['originales/src/contenido/bien.pdf']);
  });

  test('lo que llega manda sobre lo que se esperaba', () async {
    fetcher.served['https://x.org/video'] = const FakeServedFile(
      [1],
      contentType: 'audio/ogg',
      fileName: 'himno.ogg',
    );
    await offer([('https://x.org/video', RenditionKind.video, 0, null)]);

    await processor().transform(item, context: _RecordingContext());

    expect(
      (await attachments.attachmentsOf(item.id)).single.kind,
      RenditionKind.audio,
    );
  });

  test('cancelado, corta', () async {
    fetcher.served['https://x.org/a.pdf'] = FakeServedFile(
      const [1],
      contentType: 'application/pdf',
      error: DioException.requestCancelled(
        requestOptions: RequestOptions(),
        reason: 'se borró',
      ),
    );
    await offer([('https://x.org/a.pdf', RenditionKind.pdf, 0, null)]);
    final context = _RecordingContext()..cancellation.cancel();

    await expectLater(
      processor().transform(item, context: context),
      throwsA(isA<ProcessingCancelledException>()),
    );
  });

  test('sin quien baje (la web), no hay trabajo ni se intenta', () async {
    await offer([('https://x.org/a.pdf', RenditionKind.pdf, 0, null)]);

    expect(await processor(withFetcher: false).hasWork(item.id), isFalse);
    await processor(
      withFetcher: false,
    ).transform(item, context: _RecordingContext());
    expect(statuses().values.single, AttachmentDownloadStatus.pending);
  });
}
