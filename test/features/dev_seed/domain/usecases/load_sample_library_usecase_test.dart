import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
import 'package:sinapsis/features/dev_seed/domain/entities/sample_library_progress.dart';
import 'package:sinapsis/features/dev_seed/domain/entities/sample_resource.dart';
import 'package:sinapsis/features/dev_seed/domain/sample_library.dart';
import 'package:sinapsis/features/dev_seed/domain/services/sample_file_downloader.dart';
import 'package:sinapsis/features/dev_seed/domain/usecases/load_sample_library_usecase.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

import '../../../../support/fake_id_generator.dart';
import '../../dev_seed_fakes.dart';

const _web = SampleLink(
  id: 'web-roma',
  title: 'Imperio romano',
  why: 'Una página.',
  kind: SampleLinkKind.webArticle,
  url: 'https://es.wikipedia.org/wiki/Imperio_romano',
  approxBytes: 1000,
);

const _video = SampleLink(
  id: 'yt-caverna',
  title: 'La alegoría de la caverna',
  why: 'Un video.',
  kind: SampleLinkKind.youtubeVideo,
  url: 'https://www.youtube.com/watch?v=h3UJWsIfwsg',
  approxBytes: 6000,
);

const _pdf = SampleFile(
  id: 'pdf-laudato',
  title: "Laudato si'",
  why: 'Un PDF.',
  kind: SampleFileKind.pdf,
  url: 'https://ejemplo.org/laudato.pdf',
  fileName: 'laudato_si.pdf',
  approxBytes: 2000,
);

const _audio = SampleFile(
  id: 'audio-apologia',
  title: 'Apología de Sócrates',
  why: 'Un audio.',
  kind: SampleFileKind.audio,
  url: 'https://ejemplo.org/apologia.mp3',
  fileName: 'apologia.mp3',
  approxBytes: 3000,
);

const _note = SampleNote(
  id: 'nota-nicea',
  title: 'Nicea',
  why: 'Una nota.',
  blocks: [
    ContentBlock.heading(text: 'Nicea, 325'),
    ContentBlock.paragraph(text: 'Ver [[Mapa: Padres de la Iglesia]].'),
  ],
);

void main() {
  late FakeCaptureItem capture;
  late FakeLibraryRepository repository;
  late InMemorySampleLibraryLedger ledger;
  late FakeSampleFileDownloader downloader;
  late List<String> enqueued;

  // En UTC: así vuelve la fecha de un bloque al leer el JSON guardado.
  final now = DateTime.utc(2026, 10, 3, 10);

  setUp(() {
    capture = FakeCaptureItem();
    repository = FakeLibraryRepository();
    ledger = InMemorySampleLibraryLedger();
    downloader = FakeSampleFileDownloader();
    enqueued = [];
  });

  LoadSampleLibraryUseCase build(
    List<SampleResource> resources, {
    int batchSize = 10,
    int parallelDownloads = 3,
    Duration sameHostGap = Duration.zero,
  }) => LoadSampleLibraryUseCase(
    resources: resources,
    ledger: ledger,
    downloader: downloader,
    captureItem: capture,
    repository: repository,
    enqueue: enqueued.add,
    ids: FakeIdGenerator(),
    clock: () => now,
    batchSize: batchSize,
    parallelDownloads: parallelDownloads,
    sameHostGap: sameHostGap,
  );

  group('cada tipo por su camino', () {
    test('un enlace se captura por su dirección, como si se la pegara, y se '
        'encola', () async {
      final report = await build([_web, _video])(
        cancellation: CancellationSignal(),
      );

      expect(report.loaded, 2);
      expect(capture.requests, [
        const CaptureRequest.text(rawInput: _webUrl),
        const CaptureRequest.text(rawInput: _videoUrl),
      ]);
      expect(enqueued, ['item-1', 'item-2']);
      expect(downloader.downloaded, isEmpty);
      expect(repository.saved, isEmpty);
    });

    test('un archivo se baja, se captura como archivo con su título, se '
        'encola y el temporal se borra', () async {
      final report = await build([_pdf, _audio])(
        cancellation: CancellationSignal(),
      );

      expect(report.loaded, 2);
      expect(downloader.downloaded, ['pdf-laudato', 'audio-apologia']);
      expect(downloader.discarded, ['pdf-laudato', 'audio-apologia']);

      final files = capture.requests.cast<FileCapture>();
      expect(files.map((r) => r.title), [
        "Laudato si'",
        'Apología de Sócrates',
      ]);
      expect(files.map((r) => r.file.name), ['laudato_si.pdf', 'apologia.mp3']);
      expect(files.map((r) => r.file.format.sourceKind), [
        SourceKind.document,
        SourceKind.audio,
      ]);
      expect(enqueued, ['item-1', 'item-2']);
    });

    test('una nota se guarda como la guarda el editor de bloques, lista y '
        'sin encolarse', () async {
      final report = await build([_note])(cancellation: CancellationSignal());

      expect(report.loaded, 1);
      expect(capture.requests, isEmpty);
      expect(enqueued, isEmpty);

      final saved = repository.saved.single;
      expect(saved.title, 'Nicea');
      expect(saved.source.kind, SourceKind.manualNote);
      expect(saved.processingState, ProcessingState.ready);

      final rendition = saved.renditions.single as TextRendition;
      expect(rendition.kind, RenditionKind.blocks);
      expect(rendition.itemId, saved.id);
      expect(rendition.isPrimary, isTrue);
      expect(decodeContentBlocks(rendition.content), [
        ContentBlock.heading(text: 'Nicea, 325', addedAt: now),
        ContentBlock.paragraph(
          text: 'Ver [[Mapa: Padres de la Iglesia]].',
          addedAt: now,
        ),
      ]);
    });
  });

  group('no duplica', () {
    test('una segunda pasada no vuelve a cargar lo que ya se cargó', () async {
      final load = build([_web, _pdf, _note]);
      await load(cancellation: CancellationSignal());
      final requestsAfterFirst = capture.requests.length;

      final again = await load(cancellation: CancellationSignal());

      expect(again.loaded, 0);
      expect(again.alreadyLoaded, 3);
      expect(again.progress.total, 0);
      expect(capture.requests, hasLength(requestsAfterFirst));
      expect(repository.saved, hasLength(1));
      expect(downloader.downloaded, ['pdf-laudato']);
      expect(load.pending(), isEmpty);
    });

    test('lo cargado se anota uno por uno, con su id estable', () async {
      await build([_web, _note])(cancellation: CancellationSignal());

      expect(ledger.ids, {'web-roma', 'nota-nicea'});
    });
  });

  group('si uno falla', () {
    test('sigue con los demás, informa cuál y por qué, y la próxima pasada '
        'reintenta solo ese', () async {
      downloader = FakeSampleFileDownloader(failFor: {'pdf-laudato'});
      capture = FakeCaptureItem(failFor: {_videoUrl});
      final load = build([_web, _pdf, _video, _audio, _note]);

      final report = await load(cancellation: CancellationSignal());

      expect(report.loaded, 3);
      expect(report.cancelled, isFalse);
      expect(report.failures, [
        const SampleLoadFailure(
          title: "Laudato si'",
          reason: 'El servidor respondió 404.',
        ),
        const SampleLoadFailure(
          title: 'La alegoría de la caverna',
          reason: 'No se pudo guardar.',
        ),
      ]);
      expect(ledger.ids, {'web-roma', 'audio-apologia', 'nota-nicea'});
      expect(load.pending(), [_pdf, _video]);
    });

    test('un archivo que no es del tipo esperado no se guarda —una página '
        'de error en vez del PDF— y el temporal se borra igual', () async {
      downloader = FakeSampleFileDownloader(
        overrides: {
          'pdf-laudato': Uint8List.fromList(
            utf8.encode('<!DOCTYPE html><html>No encontrado</html>'),
          ),
        },
      );

      final report = await build([_pdf])(cancellation: CancellationSignal());

      expect(report.loaded, 0);
      expect(report.failures.single.title, "Laudato si'");
      expect(report.failures.single.reason, contains('pdf'));
      expect(capture.requests, isEmpty);
      expect(downloader.discarded, ['pdf-laudato']);
      expect(ledger.ids, isEmpty);
    });
  });

  group('cancelar', () {
    test('corta la bajada en curso, no empieza nada más, y la próxima pasada '
        'sigue desde donde quedó', () async {
      downloader = FakeSampleFileDownloader(
        blockUntilCancelled: {'audio-apologia'},
      );
      final load = build(
        [_web, _audio, _pdf, _note],
        batchSize: 2,
        parallelDownloads: 1,
      );
      final cancellation = CancellationSignal();

      final running = load(cancellation: cancellation);
      await downloader.blocked.future;
      cancellation.cancel();
      final report = await running;

      expect(report.cancelled, isTrue);
      expect(report.loaded, 1);
      // Lo cortado no es un fallo: queda para la próxima pasada.
      expect(report.failures, isEmpty);
      expect(ledger.ids, {'web-roma'});
      expect(downloader.downloaded, isEmpty);
      expect(load.pending(), [_audio, _pdf, _note]);

      downloader = FakeSampleFileDownloader();
      final resumed = await build([_web, _audio, _pdf, _note])(
        cancellation: CancellationSignal(),
      );
      expect(resumed.loaded, 3);
      expect(resumed.alreadyLoaded, 1);
    });

    test('cancelada antes de empezar, no carga nada', () async {
      final report = await build([_web, _note])(
        cancellation: CancellationSignal()..cancel(),
      );

      expect(report.cancelled, isTrue);
      expect(report.loaded, 0);
      expect(capture.requests, isEmpty);
      expect(repository.saved, isEmpty);
    });
  });

  test(
    'va por tandas, avisa el avance y borra lo que haya quedado de antes',
    () async {
      final progress = <SampleLoadProgress>[];

      final report = await build(
        [_web, _video, _pdf, _audio, _note],
        batchSize: 2,
      )(cancellation: CancellationSignal(), onProgress: progress.add);

      expect(downloader.leftoversCleared, 1);
      expect(report.progress.batches, 3);
      expect(progress.first.batch, 0);
      expect(progress.first.total, 5);
      expect(progress.map((p) => p.batch).toSet(), {0, 1, 2, 3});
      expect(progress.last.done, 5);
      // El avance nunca retrocede.
      final dones = progress.map((p) => p.done).toList();
      for (var i = 1; i < dones.length; i++) {
        expect(dones[i], greaterThanOrEqualTo(dones[i - 1]));
      }
    },
  );

  group('de a un archivo por servidor', () {
    // Una bajada que tarda: si dos del mismo servidor se pisaran, se vería.
    late _SlowDownloader slow;

    setUp(() {
      slow = _SlowDownloader();
      downloader = slow;
    });

    test('dos archivos del mismo servidor nunca se bajan a la vez', () async {
      // `_pdf` y `_audio` vienen los dos de ejemplo.org: así se pidieron
      // tres a la vez a Wikimedia y respondió «429, demasiados pedidos».
      final report = await build([_pdf, _audio])(
        cancellation: CancellationSignal(),
      );

      expect(report.loaded, 2);
      expect(slow.maxAtOnce['ejemplo.org'], 1);
    });

    test('los de servidores distintos sí van a la vez', () async {
      const other = SampleFile(
        id: 'audio-otro',
        title: 'Otro audio',
        why: 'De otro servidor.',
        kind: SampleFileKind.audio,
        url: 'https://archivo.org/otro.mp3',
        fileName: 'otro.mp3',
        approxBytes: 3000,
      );

      await build([_pdf, other])(cancellation: CancellationSignal());

      expect(slow.maxOverall, 2);
    });
  });

  group('la lista real', () {
    test('tiene unos 80 recursos con ids únicos y de todos los tipos', () {
      expect(sampleLibrary.length, inInclusiveRange(75, 85));
      expect(
        sampleLibrary.map((r) => r.id).toSet(),
        hasLength(sampleLibrary.length),
      );

      final links = sampleLibrary.whereType<SampleLink>();
      final files = sampleLibrary.whereType<SampleFile>();
      expect(
        links.where((l) => l.kind == SampleLinkKind.webArticle).length,
        greaterThanOrEqualTo(20),
      );
      final videos = links.where((l) => l.kind == SampleLinkKind.youtubeVideo);
      expect(videos.length, greaterThanOrEqualTo(12));
      expect(videos.where((v) => (v.minutes ?? 0) < 10), isNotEmpty);
      expect(videos.where((v) => (v.minutes ?? 0) >= 120).length, 2);
      for (final kind in SampleFileKind.values) {
        expect(files.where((f) => f.kind == kind), isNotEmpty, reason: '$kind');
      }
      expect(
        sampleLibrary.whereType<SampleNote>().length,
        inInclusiveRange(8, 12),
      );
    });

    test('cada enlace lo reconoce el adaptador que corresponde', () {
      for (final link in sampleLibrary.whereType<SampleLink>()) {
        final url = CaptureRequest.text(rawInput: link.url).asUrl;
        expect(url, isNotNull, reason: link.url);
        final isYouTube = url!.host.contains('youtube.com');
        expect(
          isYouTube,
          link.kind == SampleLinkKind.youtubeVideo,
          reason: link.url,
        );
      }
    });

    test('las notas enlazan sobre todo a otras notas o a lo que se carga, y '
        'dejan dos enlaces rotos a propósito', () {
      final titles = {
        for (final resource in sampleLibrary) resource.title.toLowerCase(),
      };
      final pattern = RegExp(r'\[\[(.+?)\]\]');
      final targets = {
        for (final note in sampleLibrary.whereType<SampleNote>())
          for (final block in note.blocks)
            for (final match in pattern.allMatches(block.text))
              match.group(1)!.toLowerCase(),
      };

      expect(targets.where((t) => !titles.contains(t)), {
        'la alegoría de la caverna',
        'carlomagno y el renacimiento carolingio',
      });
    });
  });
}

const _webUrl = 'https://es.wikipedia.org/wiki/Imperio_romano';
const _videoUrl = 'https://www.youtube.com/watch?v=h3UJWsIfwsg';

/// Un descargador de mentira que tarda un poco en cada bajada y anota
/// cuántas había a la vez, por servidor y en total.
class _SlowDownloader extends FakeSampleFileDownloader {
  final _active = <String, int>{};
  final maxAtOnce = <String, int>{};
  var _overall = 0;
  int maxOverall = 0;

  @override
  Future<DownloadedSample> download(
    SampleFile resource, {
    required CancellationSignal cancellation,
  }) async {
    final host = Uri.parse(resource.url).host;
    final now = (_active[host] ?? 0) + 1;
    _active[host] = now;
    if (now > (maxAtOnce[host] ?? 0)) maxAtOnce[host] = now;
    _overall++;
    if (_overall > maxOverall) maxOverall = _overall;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return await super.download(resource, cancellation: cancellation);
    } finally {
      _active[host] = _active[host]! - 1;
      _overall--;
    }
  }
}
