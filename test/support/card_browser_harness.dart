import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/card_phase.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/flashcards/data/repositories/card_browser_repository_impl.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_scope_resolver.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/notebooks/data/repositories/notebook_repository_impl.dart';

import 'fake_id_generator.dart';
import 'in_memory_file_store.dart';
import 'item_rows.dart';

class _MockTelemetry extends Mock implements TelemetryService {}

/// Una base en memoria con el repositorio de «Mis tarjetas» y el de las
/// estadísticas encima (F31, ola 2): lo que comparten todas las pruebas de
/// esas dos pantallas.
class CardBrowserHarness {
  CardBrowserHarness._(
    this.db,
    this.telemetry,
    this._resolver,
    this.notebooks,
    this._clock,
  );

  final AppDatabase db;
  final TelemetryService telemetry;
  final StudyScopeResolver _resolver;
  final DateTime Function() _clock;

  /// Las 10:00 del 8 de octubre de 2026: el día de estudio va de las 4:00 de
  /// hoy a las 4:00 de mañana.
  static final defaultNow = DateTime(2026, 10, 8, 10);

  static Future<CardBrowserHarness> create({
    required DateTime Function() clock,
  }) async {
    final db = AppDatabase(NativeDatabase.memory());
    final telemetry = _MockTelemetry();
    final library = LibraryRepositoryImpl(
      database: db,
      telemetry: telemetry,
      files: InMemoryFileStore(),
    );
    final notebooks = NotebookRepositoryImpl(
      database: db,
      telemetry: telemetry,
      ids: FakeIdGenerator(prefix: 'nb'),
      clock: clock,
    );
    final harness = CardBrowserHarness._(
      db,
      telemetry,
      StudyScopeResolver(library: library, notebooks: notebooks),
      notebooks,
      clock,
    );
    await insertItemRows(db, id: 'item', title: 'Un elemento');
    return harness;
  }

  final NotebookRepositoryImpl notebooks;

  CardBrowserRepositoryImpl get browser => CardBrowserRepositoryImpl(
    database: db,
    telemetry: telemetry,
    clock: _clock,
    resolver: _resolver,
  );

  StudyScopeResolver get resolver => _resolver;

  Future<void> close() => db.close();

  /// Una tarjeta, directo en la tabla, en la etapa que se pida. [interval]
  /// pisa el intervalo de la etapa de repaso.
  Future<void> card(
    String id, {
    String itemId = 'item',
    String? front,
    String? back,
    CardPhase phase = CardPhase.review,
    DateTime? dueAt,
    DateTime? createdAt,
    bool suspended = false,
    DateTime? buriedUntil,
    int? interval,
    int? learningStep,
    double ease = 2.5,
  }) {
    final (repetitions, days, step, reviewed) = switch (phase) {
      CardPhase.newCard => (0, 0, null, null),
      CardPhase.learning => (0, 0, learningStep ?? 0, DateTime(2026, 10, 8, 9)),
      CardPhase.relearning => (
        0,
        interval ?? 1,
        learningStep ?? 0,
        DateTime(2026, 10, 8, 9),
      ),
      CardPhase.review => (3, interval ?? 15, null, DateTime(2026, 9, 20)),
    };
    return db
        .into(db.flashcards)
        .insert(
          FlashcardsCompanion.insert(
            id: id,
            itemId: itemId,
            front: front ?? 'Pregunta $id',
            back: back ?? 'Respuesta $id',
            dueAt: dueAt ?? _clock(),
            createdAt: createdAt ?? DateTime(2026, 9),
            easeFactor: Value(ease),
            repetitions: Value(repetitions),
            intervalDays: Value(days),
            learningStep: Value(step),
            lastReviewedAt: Value(reviewed),
            suspended: Value(suspended),
            buriedUntil: Value(buriedUntil),
          ),
        );
  }

  var _logCounter = 0;

  /// Una respuesta ya dada, en el log.
  Future<void> answered(
    String cardId, {
    required CardPhase phase,
    required DateTime at,
    String grade = 'good',
    int intervalBefore = 0,
    int intervalAfter = 0,
  }) => db
      .into(db.reviewLogs)
      .insert(
        ReviewLogsCompanion.insert(
          id: 'log-${_logCounter++}',
          flashcardId: cardId,
          reviewedAt: at,
          grade: grade,
          quality: switch (grade) {
            'again' => 0,
            'hard' => 3,
            'good' => 4,
            _ => 5,
          },
          intervalBefore: intervalBefore,
          intervalAfter: intervalAfter,
          easeBefore: 2.5,
          easeAfter: 2.5,
          deviceId: 'dispositivo',
          phaseBefore: Value(phase),
        ),
      );
}
