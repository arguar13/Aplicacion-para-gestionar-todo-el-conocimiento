import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/creations/data/creation_files.dart';
import 'package:sinapsis/features/creations/data/repositories/study_creation_repository_impl.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';

import '../../../support/in_memory_file_store.dart';
import '../creations_harness.dart';

class _Telemetry extends Mock implements TelemetryService {}

/// F47, paso 6b: lo hecho de una generación larga, guardado con los archivos
/// de la creación para retomarla —las vueltas de un podcast, su guion
/// mientras se genera la voz—, y el audio que el contenido nombra con
/// `audio_ref`.
void main() {
  late CreationsHarness h;
  late InMemoryFileStore files;
  late StudyCreationRepositoryImpl repository;

  setUp(() async {
    h = await CreationsHarness.create();
    files = InMemoryFileStore();
    repository = StudyCreationRepositoryImpl(
      database: h.processed.db,
      telemetry: _Telemetry(),
      clock: () => h.processed.vault.now,
      files: files,
    );
  });
  tearDown(() => h.close());

  Future<StudyCreation> create() async => (await repository.create(
    const CreationRequest(
      kind: StudyCreationKind.podcast,
      scope: CreationScope.allProcessed(),
      sourceIds: ['p-1'],
    ),
  )).getRight().toNullable()!;

  Future<String?> checkpoint(String id) async =>
      (await repository.checkpoint(id)).getRight().toNullable();

  test('se guarda y se lee, en lugar del de antes, con los archivos de la '
      'creación', () async {
    final c = await create();
    expect(await checkpoint(c.id), isNull);

    expect((await repository.saveCheckpoint(c.id, '{"v":1}')).isRight(), true);
    expect(await checkpoint(c.id), '{"v":1}');
    expect(files.paths.single, startsWith('originales/${c.id}/avance/'));

    await repository.saveCheckpoint(c.id, '{"v":2}');
    expect(await checkpoint(c.id), '{"v":2}');
    expect(files.paths, hasLength(1));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('«Reintentar» lo conserva; «Volver a generar», terminarla y borrarla '
      'para siempre, no', () async {
    final c = await create();
    await repository.saveCheckpoint(c.id, 'hecho');
    await repository.fail(c.id, CreationFailure.error);

    await repository.requeue(c.id, keepCheckpoint: true);
    expect(await checkpoint(c.id), 'hecho');

    await repository.requeue(c.id, options: const {'format': 'brief'});
    expect(await checkpoint(c.id), isNull);

    await repository.saveCheckpoint(c.id, 'otra vez');
    await repository.complete(c.id, title: 'Listo', content: '{}');
    expect(await checkpoint(c.id), isNull);

    await repository.saveCheckpoint(c.id, 'de nuevo');
    await repository.trash(c.id);
    await repository.purge([c.id]);
    expect(files.paths, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('sin almacén de archivos, o de una que ya no está, no guarda y lo '
      'dice', () async {
    final bare = StudyCreationRepositoryImpl(
      database: h.processed.db,
      telemetry: _Telemetry(),
      clock: () => h.processed.vault.now,
    );
    final c = await create();
    expect((await bare.saveCheckpoint(c.id, 'x')).isLeft(), isTrue);
    expect((await bare.checkpoint(c.id)).getRight().toNullable(), isNull);

    expect((await repository.saveCheckpoint('no-existe', 'x')).isLeft(), true);
    expect(files.paths, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('uno cortado a mitad de escribirse cuenta como que no hay', () async {
    final c = await create();
    await files.saveStream(
      bytes: Stream.value([0xC3, 0x28]),
      suggestedName: 'avance.json',
      id: c.id,
      folder: 'avance',
    );
    expect(await checkpoint(c.id), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('guardar un contenido barre el audio que ya no nombra con '
      '`audio_ref`; el nombrado y lo de otras quedan', () async {
    final c = await create();
    final other = await create();
    Future<String> audio(String id, String name) => files.saveStream(
      bytes: Stream.value([1, 2, 3]),
      suggestedName: name,
      id: id,
      folder: kCreationAudioFolder,
    );
    final old = await audio(c.id, 'podcast-viejo.m4a');
    final fresh = await audio(c.id, 'podcast-nuevo.m4a');
    final theirs = await audio(other.id, 'podcast.m4a');

    await repository.complete(
      c.id,
      title: 'Podcast',
      content: jsonEncode({
        'audio': {'audio_ref': fresh},
      }),
    );
    expect(files.deleted, [old]);
    expect(files.paths, unorderedEquals([fresh, theirs]));
  }, timeout: const Timeout(Duration(seconds: 30)));
}
