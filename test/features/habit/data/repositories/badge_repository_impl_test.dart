import 'package:async/async.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/entities/habit_event_kind.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/habit/data/repositories/badge_repository_impl.dart';
import 'package:sinapsis/features/habit/domain/entities/badge_kind.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';

import '../../../../support/in_memory_file_store.dart';
import '../../../../support/item_rows.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Las seis insignias de D7, contra SQLite real.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  final today = DateTime(2026, 9, 25, 10);
  var counter = 0;

  BadgeRepositoryImpl repository({DateTime? now}) => BadgeRepositoryImpl(
    database: db,
    telemetry: MockTelemetryService(),
    clock: () => now ?? today,
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
    );
    counter = 0;
  });

  tearDown(() => db.close());

  Future<String> seedSource() async {
    final id = 'src-${counter++}';
    await library.save(
      KnowledgeItem(
        id: id,
        title: 'Fuente $id',
        source: Source(
          id: 'origin-$id',
          kind: SourceKind.webPage,
          capturedAt: today,
        ),
        processingState: ProcessingState.ready,
        createdAt: today,
        updatedAt: today,
      ),
    );
    return id;
  }

  Future<String> seedNote({
    NoteKind kind = NoteKind.living,
    NoteMaturity maturity = NoteMaturity.seed,
  }) async {
    final id = 'note-${counter++}';
    await library.save(
      KnowledgeItem(
        id: id,
        title: 'Nota $id',
        source: Source(
          id: 'origin-$id',
          kind: SourceKind.manualNote,
          capturedAt: today,
        ),
        processingState: ProcessingState.ready,
        createdAt: today,
        updatedAt: today,
      ),
    );
    await (db.update(
      db.knowledgeNotes,
    )..where((n) => n.itemId.equals(id))).write(
      KnowledgeNotesCompanion(noteKind: Value(kind), maturity: Value(maturity)),
    );
    return id;
  }

  Future<void> relate(
    String from,
    String to, {
    RelationKind kind = RelationKind.relatedTo,
    DateTime? reviewedAt,
  }) => db
      .into(db.relations)
      .insert(
        RelationsCompanion.insert(
          id: 'rel-$from-$to-${kind.name}',
          fromItemId: from,
          toItemId: to,
          kind: kind,
          createdAt: today,
          reviewedAt: Value(reviewedAt),
        ),
      );

  Future<void> addReview(DateTime at) async {
    final itemId = await seedSource();
    final cardId = 'card-${counter++}';
    await db
        .into(db.flashcards)
        .insert(
          FlashcardsCompanion.insert(
            id: cardId,
            itemId: itemId,
            front: 'p',
            back: 'r',
            dueAt: at,
            createdAt: at,
          ),
        );
    await db
        .into(db.reviewLogs)
        .insert(
          ReviewLogsCompanion.insert(
            id: 'rev-${counter++}',
            flashcardId: cardId,
            reviewedAt: at,
            grade: 'good',
            quality: 4,
            intervalBefore: 1,
            intervalAfter: 3,
            easeBefore: 2.5,
            easeAfter: 2.5,
            deviceId: 'dispositivo',
          ),
        );
  }

  Future<String> addTema(String label, {String? parentId}) async {
    final id = 'tema-${counter++}';
    final definitionId = await temaDefinitionId(db);
    await db
        .into(db.propertyValues)
        .insert(
          PropertyValuesCompanion.insert(
            id: id,
            definitionId: definitionId,
            value: label,
            parentId: Value(parentId),
            createdAt: today,
          ),
        );
    return id;
  }

  Future<void> assignTema(String itemId, String temaId) => db
      .into(db.itemPropertyValues)
      .insert(
        ItemPropertyValuesCompanion.insert(
          itemId: itemId,
          propertyValueId: temaId,
        ),
      );

  test('sin nada en la bóveda, ninguna insignia', () async {
    final earned = await repository().earned();

    expect(earned, isEmpty);
  });

  group('primera nota madura', () {
    test('una nota madura la gana', () async {
      await seedNote(maturity: NoteMaturity.mature);

      final earned = await repository().earned();

      expect(earned, contains(BadgeKind.firstMatureNote));
    });

    test('en desarrollo, todavía no', () async {
      await seedNote(maturity: NoteMaturity.developing);

      final earned = await repository().earned();

      expect(earned, isNot(contains(BadgeKind.firstMatureNote)));
    });

    test('una nota madura en la papelera no cuenta', () async {
      final id = await seedNote(maturity: NoteMaturity.mature);
      await trashItemRows(db, id);

      final earned = await repository().earned();

      expect(earned, isNot(contains(BadgeKind.firstMatureNote)));
    });
  });

  group('diez notas vivas', () {
    test('con nueve, todavía no', () async {
      for (var i = 0; i < 9; i++) {
        await seedNote();
      }

      final earned = await repository().earned();

      expect(earned, isNot(contains(BadgeKind.tenLivingNotes)));
    });

    test('con diez, sí', () async {
      for (var i = 0; i < 10; i++) {
        await seedNote();
      }

      final earned = await repository().earned();

      expect(earned, contains(BadgeKind.tenLivingNotes));
    });

    test('una nota atómica no suma para esta insignia', () async {
      for (var i = 0; i < 9; i++) {
        await seedNote();
      }
      await seedNote(kind: NoteKind.atomic);

      final earned = await repository().earned();

      expect(earned, isNot(contains(BadgeKind.tenLivingNotes)));
    });
  });

  group('cien tarjetas repasadas', () {
    test('con noventa y nueve, todavía no', () async {
      for (var i = 0; i < 99; i++) {
        await addReview(today);
      }

      final earned = await repository().earned();

      expect(earned, isNot(contains(BadgeKind.hundredReviews)));
    });

    test('con cien, sí —repasos distintos, no tarjetas distintas—', () async {
      final itemId = await seedSource();
      const cardId = 'card-fijo';
      await db
          .into(db.flashcards)
          .insert(
            FlashcardsCompanion.insert(
              id: cardId,
              itemId: itemId,
              front: 'p',
              back: 'r',
              dueAt: today,
              createdAt: today,
            ),
          );
      for (var i = 0; i < 100; i++) {
        await db
            .into(db.reviewLogs)
            .insert(
              ReviewLogsCompanion.insert(
                id: 'rev-repetido-$i',
                flashcardId: cardId,
                reviewedAt: today,
                grade: 'good',
                quality: 4,
                intervalBefore: 1,
                intervalAfter: 3,
                easeBefore: 2.5,
                easeAfter: 2.5,
                deviceId: 'dispositivo',
              ),
            );
      }

      final earned = await repository().earned();

      expect(earned, contains(BadgeKind.hundredReviews));
    });
  });

  group('una contradicción resuelta', () {
    test('marcada como revisada, la gana', () async {
      final a = await seedSource();
      final b = await seedSource();
      await relate(a, b, kind: RelationKind.contradicts, reviewedAt: today);

      final earned = await repository().earned();

      expect(earned, contains(BadgeKind.contradictionResolved));
    });

    test('sin revisar, todavía no', () async {
      final a = await seedSource();
      final b = await seedSource();
      await relate(a, b, kind: RelationKind.contradicts);

      final earned = await repository().earned();

      expect(earned, isNot(contains(BadgeKind.contradictionResolved)));
    });

    test('un vínculo revisado que no es contradicts no cuenta', () async {
      final a = await seedSource();
      final b = await seedSource();
      await relate(a, b, reviewedAt: today);

      final earned = await repository().earned();

      expect(earned, isNot(contains(BadgeKind.contradictionResolved)));
    });
  });

  group('un tema completo de punta a punta', () {
    test('una rama con el piso mínimo, toda citada por una nota madura, '
        'la gana', () async {
      final tema = await addTema('Roma');
      final sources = [
        await seedSource(),
        await seedSource(),
        await seedSource(),
      ];
      for (final id in sources) {
        await assignTema(id, tema);
      }
      final note = await seedNote(maturity: NoteMaturity.mature);
      for (final id in sources) {
        await relate(note, id, kind: RelationKind.extractedFrom);
      }

      final earned = await repository().earned();

      expect(earned, contains(BadgeKind.completeTopicBranch));
    });

    test('menos del piso, aunque esté toda citada, no alcanza', () async {
      final tema = await addTema('Roma');
      final sources = [await seedSource(), await seedSource()];
      for (final id in sources) {
        await assignTema(id, tema);
      }
      final note = await seedNote(maturity: NoteMaturity.mature);
      for (final id in sources) {
        await relate(note, id, kind: RelationKind.extractedFrom);
      }

      final earned = await repository().earned();

      expect(earned, isNot(contains(BadgeKind.completeTopicBranch)));
    });

    test('con una fuente sin citar, no alcanza', () async {
      final tema = await addTema('Roma');
      final sources = [
        await seedSource(),
        await seedSource(),
        await seedSource(),
      ];
      for (final id in sources) {
        await assignTema(id, tema);
      }
      final note = await seedNote(maturity: NoteMaturity.mature);
      // Solo dos de las tres.
      for (final id in sources.take(2)) {
        await relate(note, id, kind: RelationKind.extractedFrom);
      }

      final earned = await repository().earned();

      expect(earned, isNot(contains(BadgeKind.completeTopicBranch)));
    });

    test('una nota que cita pero no es madura no alcanza', () async {
      final tema = await addTema('Roma');
      final sources = [
        await seedSource(),
        await seedSource(),
        await seedSource(),
      ];
      for (final id in sources) {
        await assignTema(id, tema);
      }
      final note = await seedNote(maturity: NoteMaturity.developing);
      for (final id in sources) {
        await relate(note, id, kind: RelationKind.extractedFrom);
      }

      final earned = await repository().earned();

      expect(earned, isNot(contains(BadgeKind.completeTopicBranch)));
    });

    test('las citadas de una subrama completan a la rama padre', () async {
      final historia = await addTema('Historia');
      final roma = await addTema('Roma', parentId: historia);
      final sources = [
        await seedSource(),
        await seedSource(),
        await seedSource(),
      ];
      for (final id in sources) {
        await assignTema(id, roma);
      }
      final note = await seedNote(maturity: NoteMaturity.mature);
      for (final id in sources) {
        await relate(note, id, kind: RelationKind.extractedFrom);
      }

      final earned = await repository().earned();

      // «historia» hereda las 3 fuentes de «roma»: también cuenta, ya
      // completa la insignia con solo que una rama alcance.
      expect(earned, contains(BadgeKind.completeTopicBranch));
    });
  });

  group('un mes de consolidación semanal', () {
    test('con actividad en cada semana ya empezada del mes, la gana', () async {
      await addReview(DateTime(2026, 9, 3));
      await addReview(DateTime(2026, 9, 9));

      final earned = await repository(now: DateTime(2026, 9, 10)).earned();

      expect(earned, contains(BadgeKind.monthOfWeeklyConsolidation));
    });

    test('con una semana sin nada, todavía no', () async {
      await addReview(DateTime(2026, 9, 3));

      final earned = await repository(now: DateTime(2026, 9, 10)).earned();

      expect(earned, isNot(contains(BadgeKind.monthOfWeeklyConsolidation)));
    });

    test('un evento de hábito también cuenta como actividad', () async {
      await db
          .into(db.habitEvents)
          .insert(
            HabitEventsCompanion.insert(
              id: 'ev-1',
              kind: HabitEventKind.triage,
              occurredAt: DateTime(2026, 9),
            ),
          );

      final earned = await repository(now: DateTime(2026, 9)).earned();

      expect(earned, contains(BadgeKind.monthOfWeeklyConsolidation));
    });
  });

  group('watch (F17, commit 9)', () {
    test('vuelve a emitir sola cuando se gana una insignia', () async {
      final queue = StreamQueue(repository().watch());
      addTearDown(queue.cancel);
      final first = await queue.next;
      expect(first, isEmpty);

      await seedNote(maturity: NoteMaturity.mature);

      // `seedNote` hace más de una escritura (el elemento, la nota, la
      // forma de texto): puede llegar alguna emisión intermedia antes de
      // que la madurez quede puesta, así que se espera hasta que aparezca
      // en vez de mirar solo la próxima.
      var latest = await queue.next;
      while (!latest.contains(BadgeKind.firstMatureNote)) {
        latest = await queue.next.timeout(const Duration(seconds: 5));
      }
      expect(latest, contains(BadgeKind.firstMatureNote));
    });
  });
}
