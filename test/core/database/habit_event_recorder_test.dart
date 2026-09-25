import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/habit_event_recorder.dart';
import 'package:sinapsis/core/domain/entities/habit_event_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/id_generator.dart';

import '../../support/fake_id_generator.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Siempre el mismo id: sirve para forzar el choque de clave primaria que
/// prueba que un fallo al guardar no revienta nada (F17, D6).
class _FixedIdGenerator implements IdGenerator {
  @override
  String next() => 'siempre-el-mismo';
}

/// Guarda el rastro mínimo de la racha (F17, D6), contra SQLite real.
void main() {
  late AppDatabase db;
  final now = DateTime(2026, 9, 25, 9);

  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  tearDown(() => db.close());

  test('guarda el tipo y la hora de ahora', () async {
    final telemetry = MockTelemetryService();
    final recorder = HabitEventRecorder(
      database: db,
      telemetry: telemetry,
      ids: FakeIdGenerator(),
      clock: () => now,
    );

    await recorder.record(HabitEventKind.triage);

    final event = await db.select(db.habitEvents).getSingle();
    expect(event.kind, HabitEventKind.triage);
    expect(event.occurredAt, now);
    verifyNever(
      () => telemetry.recordError(
        any<Object?>(),
        any<StackTrace?>(),
        hint: any<String?>(named: 'hint'),
      ),
    );
  });

  test('cada llamada guarda su propia fila', () async {
    final recorder = HabitEventRecorder(
      database: db,
      telemetry: MockTelemetryService(),
      ids: FakeIdGenerator(),
      clock: () => now,
    );

    await recorder.record(HabitEventKind.triage);
    await recorder.record(HabitEventKind.vocabulary);

    final events = await db.select(db.habitEvents).get();
    expect(events.map((e) => e.kind).toSet(), {
      HabitEventKind.triage,
      HabitEventKind.vocabulary,
    });
  });

  test('si falla al guardar, no revienta: solo avisa a telemetría', () async {
    final telemetry = MockTelemetryService();
    final recorder = HabitEventRecorder(
      database: db,
      telemetry: telemetry,
      ids: _FixedIdGenerator(),
      clock: () => now,
    );
    await recorder.record(HabitEventKind.triage);

    // El mismo id de nuevo: choca contra la clave primaria.
    await recorder.record(HabitEventKind.vocabulary);

    expect(await db.select(db.habitEvents).get(), hasLength(1));
    verify(
      () => telemetry.recordError(
        any<Object?>(),
        any<StackTrace?>(),
        hint: 'HabitEventRecorder.record',
      ),
    ).called(1);
  });
}
