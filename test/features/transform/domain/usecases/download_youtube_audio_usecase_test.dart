import 'dart:async';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';
import 'package:sinapsis/features/transform/domain/usecases/download_youtube_audio_usecase.dart';

import '../../../../support/in_memory_file_store.dart';
import '../../../../support/transform_test_doubles.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl repository;
  late InMemoryFileStore files;

  final now = DateTime(2026, 9, 29, 10);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    files = InMemoryFileStore();
    repository = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: files,
    );
  });

  tearDown(() => db.close());

  DownloadYouTubeAudioUseCase build(FakeYouTubeClient client) =>
      DownloadYouTubeAudioUseCase(
        client: client,
        files: files,
        repository: repository,
        clock: () => now,
      );

  Future<KnowledgeItem> seedVideo() async {
    final item = KnowledgeItem(
      id: 'item-1',
      title: 'Un video',
      source: Source(
        id: 'src-1',
        kind: SourceKind.youtube,
        capturedAt: now,
        url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      ),
      processingState: ProcessingState.ready,
      createdAt: now,
      updatedAt: now,
    );
    await repository.save(item);
    return item;
  }

  Future<KnowledgeItem?> reload(String id) async =>
      (await repository.findById(id)).getRight().toNullable();

  test('guarda el audio y lo deja como el original del video', () async {
    await seedVideo();
    final audio = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7]);
    final client = FakeYouTubeClient(audio: audio);

    final saved = await build(client)('item-1');

    expect(client.audioRequested, ['dQw4w9WgXcQ']);
    final path = saved.source.originalFilePath!;
    expect(path, endsWith('.m4a'));
    expect(await files.read(path), audio);
    expect((await reload('item-1'))!.source.originalFilePath, path);
  });

  test('informa el avance a medida que llegan las partes', () async {
    await seedVideo();
    final progress = <(int, int?)>[];

    await build(FakeYouTubeClient(audio: Uint8List.fromList([1, 2, 3, 4, 5])))(
      'item-1',
      onProgress: (received, total) => progress.add((received, total)),
    );

    expect(progress, [(2, 5), (4, 5), (5, 5)]);
  });

  /// Arranca la descarga y espera a que llegue la primera parte: lo que
  /// haga el test después pasa "mientras baja". Completar [resume] deja
  /// llegar el resto.
  Future<Future<KnowledgeItem>> startPaused({
    required Future<void> resume,
    CancellationSignal? cancellation,
  }) async {
    final firstChunk = Completer<void>();
    final download =
        build(FakeYouTubeClient(audioPausedAfterFirstChunk: resume))(
          'item-1',
          cancellation: cancellation,
          onProgress: (_, _) {
            if (!firstChunk.isCompleted) firstChunk.complete();
          },
        );
    await firstChunk.future;
    return download;
  }

  test('cancelar a mitad de camino la corta en el acto y no deja ningún '
      'archivo', () async {
    await seedVideo();
    final cancellation = CancellationSignal();

    // La descarga se quedó colgada: cancelar tiene que cortarla aunque no
    // llegue nada más.
    final download = await startPaused(
      resume: Completer<void>().future,
      cancellation: cancellation,
    );
    cancellation.cancel();

    await expectLater(download, throwsA(isA<ProcessingCancelledException>()));
    expect(files.paths, isEmpty);
    expect((await reload('item-1'))!.source.originalFilePath, isNull);
  });

  test('si el video se borra mientras baja, el archivo no queda '
      'huérfano', () async {
    await seedVideo();
    final resume = Completer<void>();

    final download = await startPaused(resume: resume.future);
    await repository.delete('item-1');
    resume.complete();

    await expectLater(download, throwsA(isA<ProcessingCancelledException>()));
    expect(files.paths, isEmpty);
  });

  test('no pisa lo que el usuario cambió mientras bajaba', () async {
    final item = await seedVideo();
    final resume = Completer<void>();

    final download = await startPaused(resume: resume.future);
    await repository.save(item.copyWith(title: 'Mi título'));
    resume.complete();
    await download;

    final current = (await reload('item-1'))!;
    expect(current.title, 'Mi título');
    expect(current.source.originalFilePath, isNotNull);
  });

  test('si YouTube no lo entrega, lanza y no deja nada', () async {
    await seedVideo();

    await expectLater(
      build(FakeYouTubeClient(audioError: Exception('no disponible')))(
        'item-1',
      ),
      throwsA(isA<Exception>()),
    );
    expect(files.paths, isEmpty);
  });
}
