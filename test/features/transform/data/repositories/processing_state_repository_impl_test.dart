import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_failure_reason.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/source_processing_status.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/transform/data/repositories/processing_state_repository_impl.dart';

import '../../../../support/in_memory_file_store.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late ProcessingStateRepositoryImpl states;

  final now = DateTime(2026, 9, 29, 10);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
    );
    states = ProcessingStateRepositoryImpl(db);
  });

  tearDown(() => db.close());

  Future<void> seed(
    String id, {
    ProcessingState state = ProcessingState.pending,
    DateTime? capturedAt,
    SourceKind kind = SourceKind.webPage,
  }) async {
    final at = capturedAt ?? now;
    final result = await library.save(
      KnowledgeItem(
        id: id,
        title: 'Elemento $id',
        source: Source(
          id: 'src-$id',
          kind: kind,
          capturedAt: at,
          url: 'https://ejemplo.org/$id',
        ),
        processingState: state,
        createdAt: at,
        updatedAt: at,
      ),
    );
    expect(result.isRight(), isTrue, reason: 'no se pudo sembrar $id');
  }

  Future<KnowledgeSourceRow> sourceOf(String id) => (db.select(
    db.knowledgeSources,
  )..where((s) => s.itemId.equals(id))).getSingle();

  Future<void> setAttempts(String id, int attempts) =>
      (db.update(db.knowledgeSources)..where((s) => s.itemId.equals(id))).write(
        KnowledgeSourcesCompanion(processingAttempts: Value(attempts)),
      );

  group('begin', () {
    test('marca en curso, cuenta el intento y borra el motivo '
        'anterior', () async {
      await seed('a');
      await states.fail('a', ProcessingFailureReason.network);

      expect(await states.begin('a'), 1);
      expect(await states.begin('a'), 2);

      final row = await sourceOf('a');
      expect(row.processingStatus, SourceProcessingStatus.running);
      expect(row.processingAttempts, 2);
      expect(row.processingError, isNull);
    });

    test('sobre algo sin fila de fuente —una nota— no hace nada', () async {
      expect(await states.begin('no-existe'), 0);
    });
  });

  test('fail guarda el motivo por su nombre y conserva los intentos', () async {
    await seed('a');
    await states.begin('a');

    await states.fail('a', ProcessingFailureReason.transcriptionModelMissing);

    final row = await sourceOf('a');
    expect(row.processingStatus, SourceProcessingStatus.failed);
    expect(row.processingError, 'transcriptionModelMissing');
    expect(row.processingAttempts, 1);
    expect(
      ProcessingFailureReason.fromStored(row.processingError),
      ProcessingFailureReason.transcriptionModelMissing,
    );
  });

  test('succeed borra motivo e intentos sin tocar el estado', () async {
    await seed('a', state: ProcessingState.ready);
    await setAttempts('a', 2);

    await states.succeed('a');

    final row = await sourceOf('a');
    expect(row.processingStatus, SourceProcessingStatus.done);
    expect(row.processingAttempts, 0);
    expect(row.processingError, isNull);
  });

  test('requeue deja en espera desde cero', () async {
    await seed('a');
    await states.begin('a');
    await states.fail('a', ProcessingFailureReason.timedOut);

    await states.requeue('a');

    final row = await sourceOf('a');
    expect(row.processingStatus, SourceProcessingStatus.pending);
    expect(row.processingAttempts, 0);
    expect(row.processingError, isNull);
  });

  group('recoverInterrupted', () {
    test('lo que quedó en curso vuelve a estar en espera, en orden de '
        'captura', () async {
      await seed(
        'segundo',
        state: ProcessingState.processing,
        capturedAt: now.add(const Duration(minutes: 1)),
      );
      await seed('primero', state: ProcessingState.processing);
      await seed('listo', state: ProcessingState.ready);

      final resumed = await states.recoverInterrupted(maxAttempts: 3);

      expect(resumed, ['primero', 'segundo']);
      expect(
        (await sourceOf('primero')).processingStatus,
        SourceProcessingStatus.pending,
      );
      expect(
        (await sourceOf('listo')).processingStatus,
        SourceProcessingStatus.done,
      );
    });

    test('con el tope de intentos alcanzado pasa a fallido por '
        'interrupción, no vuelve', () async {
      // Si es él el que hace caer la app, retomarlo en cada arranque sería un
      // bucle sin fin.
      await seed('tumba-la-app', state: ProcessingState.processing);
      await setAttempts('tumba-la-app', 3);

      final resumed = await states.recoverInterrupted(maxAttempts: 3);

      expect(resumed, isEmpty);
      final row = await sourceOf('tumba-la-app');
      expect(row.processingStatus, SourceProcessingStatus.failed);
      expect(row.processingError, 'interrupted');
    });

    test('no toca lo que está en curso en esta sesión', () async {
      await seed('en-curso', state: ProcessingState.processing);

      final resumed = await states.recoverInterrupted(
        maxAttempts: 3,
        inFlight: {'en-curso'},
      );

      expect(resumed, isEmpty);
      expect(
        (await sourceOf('en-curso')).processingStatus,
        SourceProcessingStatus.running,
      );
    });

    test('lo que está en la papelera vuelve a espera pero no se '
        'devuelve para procesar', () async {
      await seed('borrado', state: ProcessingState.processing);
      await library.delete('borrado');

      final resumed = await states.recoverInterrupted(maxAttempts: 3);

      expect(resumed, isEmpty);
      expect(
        (await sourceOf('borrado')).processingStatus,
        SourceProcessingStatus.pending,
      );
    });
  });

  test('watchFailure dice por qué falló, y nada si no falló', () async {
    await seed('a');

    expect(await states.watchFailure('a').first, isNull);

    await states.fail('a', ProcessingFailureReason.network);
    expect(
      await states.watchFailure('a').first,
      ProcessingFailureReason.network,
    );

    await states.requeue('a');
    expect(await states.watchFailure('a').first, isNull);
  });

  test('requeueFailedWith vuelve a poner en espera solo lo que falló por '
      'ese motivo', () async {
    // Lo que esperaba el modelo de transcripción, al terminar de bajarlo.
    await seed('audio-1');
    await seed('audio-2');
    await seed('sin-red');
    await states.fail(
      'audio-1',
      ProcessingFailureReason.transcriptionModelMissing,
    );
    await states.fail(
      'audio-2',
      ProcessingFailureReason.transcriptionModelMissing,
    );
    await states.fail('sin-red', ProcessingFailureReason.network);

    final count = await states.requeueFailedWith(
      ProcessingFailureReason.transcriptionModelMissing,
    );

    expect(count, 2);
    expect(await states.pendingIds(), containsAll(['audio-1', 'audio-2']));
    expect(
      (await sourceOf('sin-red')).processingStatus,
      SourceProcessingStatus.failed,
    );
  });

  test('pendingIds: en espera, sin la papelera, en orden de captura', () async {
    await seed('b', capturedAt: now.add(const Duration(minutes: 2)));
    await seed('a', capturedAt: now.add(const Duration(minutes: 1)));
    await seed('borrado');
    await library.delete('borrado');
    await seed('fallido', state: ProcessingState.failed);

    expect(await states.pendingIds(), ['a', 'b']);
  });
}
