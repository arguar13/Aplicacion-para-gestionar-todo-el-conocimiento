import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/ai_rejection_memory.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/ai_provenance.dart';
import 'package:sinapsis/core/domain/entities/ai_rejection_kind.dart';
import 'package:sinapsis/core/domain/entities/ai_rejection_receipt.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/domain/entities/flashcard_option.dart';
import 'package:sinapsis/core/domain/services/ai_rejection_fingerprint.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/flashcards/data/repositories/flashcard_row_mapping.dart';
import 'package:sinapsis/features/flashcards/domain/entities/flashcard_option_draft.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/flashcards/domain/entities/sibling_card_draft.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/flashcard_repository.dart';
import 'package:sinapsis/features/flashcards/domain/services/sm2_scheduler.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_day.dart';

class FlashcardRepositoryImpl implements FlashcardRepository {
  const FlashcardRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
    required IdGenerator ids,
    required Clock clock,
    StudyDay day = const StudyDay(),
  }) : _db = database,
       _telemetry = telemetry,
       _ids = ids,
       _clock = clock,
       _day = day;

  final AppDatabase _db;
  final TelemetryService _telemetry;
  final IdGenerator _ids;
  final Clock _clock;
  final StudyDay _day;

  @override
  Future<Either<Failure, Flashcard>> create({
    required String itemId,
    required String front,
    required String back,
    int? sourceCharStart,
    int? sourceCharEnd,
    FlashcardKind kind = FlashcardKind.freeRecall,
    AiProvenance? ai,
    String? groupId,
    int? clozeIndex,
  }) async {
    final trimmedFront = front.trim();
    final trimmedBack = back.trim();
    // Una de huecos puede no traer complemento: la respuesta SON los huecos.
    final backMayBeEmpty = kind == FlashcardKind.cloze;
    if (trimmedFront.isEmpty || (trimmedBack.isEmpty && !backMayBeEmpty)) {
      return left(
        const Failure.validation(
          message: 'La pregunta y la respuesta no pueden quedar vacías.',
        ),
      );
    }
    if ((kind == FlashcardKind.cloze) != (clozeIndex != null) ||
        (clozeIndex != null && clozeIndex < 1)) {
      return left(
        const Failure.validation(
          message:
              'Una tarjeta de huecos dice cuál hueco tapa (desde 1), y las '
              'demás formas no.',
        ),
      );
    }
    final hasStart = sourceCharStart != null;
    if (hasStart != (sourceCharEnd != null) ||
        (hasStart &&
            (sourceCharStart < 0 || sourceCharEnd! <= sourceCharStart))) {
      return left(
        const Failure.validation(
          message:
              'El fragmento de la fuente tiene que traer inicio y fin, de 0 '
              'en adelante y con el fin después del inicio.',
        ),
      );
    }
    if (kind == FlashcardKind.multipleChoice) {
      return left(
        const Failure.validation(
          message:
              'Una tarjeta de opción múltiple se crea con '
              'createMultipleChoice, que también pide sus opciones.',
        ),
      );
    }

    try {
      if (ai != null && await _isRejectedQuestion(itemId, trimmedFront)) {
        return left(_rejectedQuestion);
      }
      final now = _clock();
      final chunkId = hasStart
          ? await _chunkContaining(itemId, sourceCharStart)
          : null;
      final card = Flashcard(
        id: _ids.next(),
        itemId: itemId,
        front: trimmedFront,
        back: trimmedBack,
        dueAt: now,
        createdAt: now,
        kind: kind,
        sourceChunkId: chunkId,
        sourceCharStart: sourceCharStart,
        sourceCharEnd: sourceCharEnd,
        origin: ai == null ? ContentOrigin.user : ContentOrigin.ai,
        aiRunId: ai?.runId,
        groupId: groupId,
        clozeIndex: clozeIndex,
      );

      await _db
          .into(_db.flashcards)
          .insert(
            FlashcardsCompanion.insert(
              id: card.id,
              itemId: card.itemId,
              front: card.front,
              back: card.back,
              dueAt: card.dueAt,
              createdAt: card.createdAt,
              kind: Value(card.kind),
              sourceChunkId: Value(card.sourceChunkId),
              sourceCharStart: Value(card.sourceCharStart),
              sourceCharEnd: Value(card.sourceCharEnd),
              origin: Value(card.origin),
              aiRunId: Value(card.aiRunId),
              groupId: Value(card.groupId),
              clozeIndex: Value(card.clozeIndex),
            ),
          );

      return right(card);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(_unexpected(e, stackTrace, 'FlashcardRepositoryImpl.create'));
    }
  }

  @override
  Future<Either<Failure, List<Flashcard>>> createSiblings({
    required String itemId,
    required List<SiblingCardDraft> drafts,
    AiProvenance? ai,
  }) async {
    if (drafts.length < 2) {
      return left(
        const Failure.validation(
          message: 'Un grupo de hermanas necesita al menos dos tarjetas.',
        ),
      );
    }
    final groupId = _ids.next();
    try {
      return await _db.transaction(() async {
        final created = <Flashcard>[];
        for (final draft in drafts) {
          final result = await create(
            itemId: itemId,
            front: draft.front,
            back: draft.back,
            kind: draft.kind,
            sourceCharStart: draft.sourceCharStart,
            sourceCharEnd: draft.sourceCharEnd,
            clozeIndex: draft.clozeIndex,
            groupId: groupId,
            ai: ai,
          );
          final failure = result.getLeft().toNullable();
          if (failure != null) {
            // Todas o ninguna: una hermana que falla deshace el grupo.
            throw _SiblingFailed(failure);
          }
          created.add(result.getRight().toNullable()!);
        }
        return right<Failure, List<Flashcard>>(created);
      });
    } on _SiblingFailed catch (failed) {
      return left(failed.failure);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'FlashcardRepositoryImpl.createSiblings'),
      );
    }
  }

  @override
  Future<Either<Failure, Flashcard>> createMultipleChoice({
    required String itemId,
    required String front,
    required List<FlashcardOptionDraft> options,
    AiProvenance? ai,
  }) async {
    final trimmedFront = front.trim();
    if (trimmedFront.isEmpty) {
      return left(
        const Failure.validation(message: 'La pregunta no puede quedar vacía.'),
      );
    }
    if (options.length < 2) {
      return left(
        const Failure.validation(
          message:
              'Una pregunta de opción múltiple necesita al menos dos '
              'opciones.',
        ),
      );
    }
    final trimmedOptions = [
      for (final option in options)
        FlashcardOptionDraft(
          content: option.content.trim(),
          isCorrect: option.isCorrect,
          sourceItemId: option.sourceItemId,
          sourceCharStart: option.sourceCharStart,
          sourceCharEnd: option.sourceCharEnd,
        ),
    ];
    if (trimmedOptions.any((o) => o.content.isEmpty)) {
      return left(
        const Failure.validation(message: 'Ninguna opción puede quedar vacía.'),
      );
    }
    final correctCount = trimmedOptions.where((o) => o.isCorrect).length;
    if (correctCount != 1) {
      return left(
        const Failure.validation(
          message:
              'Una pregunta de opción múltiple tiene que tener '
              'exactamente una opción correcta.',
        ),
      );
    }

    try {
      if (ai != null && await _isRejectedQuestion(itemId, trimmedFront)) {
        return left(_rejectedQuestion);
      }
      final now = _clock();
      final card = Flashcard(
        id: _ids.next(),
        itemId: itemId,
        front: trimmedFront,
        back: '',
        dueAt: now,
        createdAt: now,
        kind: FlashcardKind.multipleChoice,
        origin: ai == null ? ContentOrigin.user : ContentOrigin.ai,
        aiRunId: ai?.runId,
      );

      await _db.transaction(() async {
        await _db
            .into(_db.flashcards)
            .insert(
              FlashcardsCompanion.insert(
                id: card.id,
                itemId: card.itemId,
                front: card.front,
                back: card.back,
                dueAt: card.dueAt,
                createdAt: card.createdAt,
                kind: Value(card.kind),
                origin: Value(card.origin),
                aiRunId: Value(card.aiRunId),
              ),
            );

        for (final (position, option) in trimmedOptions.indexed) {
          final hasStart = option.sourceCharStart != null;
          final sourceItemId = hasStart
              ? (option.sourceItemId ?? itemId)
              : null;
          final chunkId = hasStart
              ? await _chunkContaining(sourceItemId!, option.sourceCharStart!)
              : null;
          await _db
              .into(_db.flashcardOptions)
              .insert(
                FlashcardOptionsCompanion.insert(
                  id: _ids.next(),
                  flashcardId: card.id,
                  content: option.content,
                  isCorrect: option.isCorrect,
                  position: position,
                  sourceChunkId: Value(chunkId),
                  sourceCharStart: Value(option.sourceCharStart),
                  sourceCharEnd: Value(option.sourceCharEnd),
                  sourceItemId: Value(sourceItemId),
                ),
              );
        }
      });

      return right(card);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(
          e,
          stackTrace,
          'FlashcardRepositoryImpl.createMultipleChoice',
        ),
      );
    }
  }

  @override
  Future<Either<Failure, List<FlashcardOption>>> optionsFor(
    String flashcardId,
  ) async {
    try {
      final rows =
          await (_db.select(_db.flashcardOptions)
                ..where((o) => o.flashcardId.equals(flashcardId))
                ..orderBy([(o) => OrderingTerm(expression: o.position)]))
              .get();
      return right(rows.map(_toOptionEntity).toList());
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'FlashcardRepositoryImpl.optionsFor'),
      );
    }
  }

  @override
  Future<Either<Failure, Flashcard>> update({
    required String id,
    required String front,
    required String back,
  }) async {
    final trimmedFront = front.trim();
    final trimmedBack = back.trim();
    if (trimmedFront.isEmpty || trimmedBack.isEmpty) {
      return left(
        const Failure.validation(
          message: 'La pregunta y la respuesta no pueden quedar vacías.',
        ),
      );
    }

    try {
      final updated =
          await (_db.update(
            _db.flashcards,
          )..where((f) => f.id.equals(id))).writeReturning(
            FlashcardsCompanion(
              front: Value(trimmedFront),
              back: Value(trimmedBack),
              // Editar es adoptar (F27): deja de ser de la IA.
              origin: const Value(ContentOrigin.user),
              aiRunId: const Value(null),
            ),
          );

      final row = updated.singleOrNull;
      if (row == null) {
        return left(
          const Failure.unexpected(
            message: 'La tarjeta ya no existe; puede que se haya borrado.',
          ),
        );
      }

      return right(_toEntity(row));
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(_unexpected(e, stackTrace, 'FlashcardRepositoryImpl.update'));
    }
  }

  @override
  Future<Either<Failure, Unit>> delete(String id) async {
    try {
      await (_db.delete(_db.flashcards)..where((f) => f.id.equals(id))).go();
      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(_unexpected(e, stackTrace, 'FlashcardRepositoryImpl.delete'));
    }
  }

  @override
  Future<Either<Failure, AiRejectionReceipt>> rejectAiFlashcard(
    String id,
  ) async {
    try {
      return await _db.transaction(() async {
        final card = await (_db.select(
          _db.flashcards,
        )..where((f) => f.id.equals(id))).getSingleOrNull();
        if (card == null) {
          return left(
            const Failure.unexpected(
              message: 'La tarjeta ya no existe; puede que se haya borrado.',
            ),
          );
        }
        if (card.origin != ContentOrigin.ai) {
          return left(
            const Failure.validation(
              message:
                  'Esa tarjeta la hizo la persona: se borra, no se le '
                  'dice a la IA que no era.',
            ),
          );
        }

        // Lo que se va con la tarjeta en cascada también se guarda: deshacer
        // tiene que devolverla entera, con sus opciones y sus repasos.
        final removed = _RemovedFlashcard(
          card: card,
          options: await (_db.select(
            _db.flashcardOptions,
          )..where((o) => o.flashcardId.equals(id))).get(),
          reviews: await (_db.select(
            _db.reviewLogs,
          )..where((r) => r.flashcardId.equals(id))).get(),
        );
        final rejectionId = await rememberAiRejection(
          _db,
          ids: _ids,
          now: _clock(),
          kind: AiRejectionKind.flashcard,
          itemId: card.itemId,
          fingerprint: flashcardRejectionFingerprint(card.front),
          subjectId: card.id,
        );
        await (_db.delete(_db.flashcards)..where((f) => f.id.equals(id))).go();
        return right(
          AiRejectionReceipt(
            kind: AiRejectionKind.flashcard,
            rejectionId: rejectionId,
            removed: removed,
          ),
        );
      });
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'FlashcardRepositoryImpl.rejectAiFlashcard'),
      );
    }
  }

  @override
  Future<Either<Failure, Unit>> restoreRejectedFlashcard(
    AiRejectionReceipt receipt,
  ) async {
    final removed = receipt.removed;
    if (receipt.kind != AiRejectionKind.flashcard ||
        removed is! _RemovedFlashcard) {
      return left(
        const Failure.validation(
          message: 'Ese comprobante no es el de una tarjeta.',
        ),
      );
    }
    try {
      await _db.transaction(() async {
        await _db
            .into(_db.flashcards)
            .insert(removed.card, mode: InsertMode.insertOrIgnore);
        for (final option in removed.options) {
          await _db
              .into(_db.flashcardOptions)
              .insert(option, mode: InsertMode.insertOrIgnore);
        }
        for (final review in removed.reviews) {
          await _db
              .into(_db.reviewLogs)
              .insert(review, mode: InsertMode.insertOrIgnore);
        }
        await forgetAiRejection(_db, receipt.rejectionId);
      });
      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(
          e,
          stackTrace,
          'FlashcardRepositoryImpl.restoreRejectedFlashcard',
        ),
      );
    }
  }

  /// Si la persona ya dijo que esta pregunta «no era» en [itemId] (F27).
  Future<bool> _isRejectedQuestion(String itemId, String question) =>
      isAiRejected(
        _db,
        kind: AiRejectionKind.flashcard,
        itemId: itemId,
        fingerprint: flashcardRejectionFingerprint(question),
      );

  static const _rejectedQuestion = Failure.validation(
    message: 'La persona ya dijo que esa tarjeta no era.',
  );

  @override
  Future<Either<Failure, Flashcard>> review({
    required String id,
    required ReviewGrade grade,
  }) async {
    try {
      // El estado de la tarjeta y el renglón del historial van juntos: o quedan
      // los dos o no queda ninguno.
      final scheduled = await _db.transaction(() async {
        final row = await (_db.select(
          _db.flashcards,
        )..where((f) => f.id.equals(id))).getSingleOrNull();
        if (row == null) return null;

        final now = _clock();
        final before = _toEntity(row);
        final next = scheduleNext(before, grade, now: now);

        await (_db.update(_db.flashcards)..where((f) => f.id.equals(id))).write(
          FlashcardsCompanion(
            easeFactor: Value(next.easeFactor),
            intervalDays: Value(next.intervalDays),
            repetitions: Value(next.repetitions),
            learningStep: Value(next.learningStep),
            dueAt: Value(next.dueAt),
            lastReviewedAt: Value(next.lastReviewedAt),
          ),
        );

        // Hasta F11 cada repaso sobrescribía el estado y el dato se perdía.
        await _db
            .into(_db.reviewLogs)
            .insert(
              ReviewLogsCompanion.insert(
                id: _ids.next(),
                flashcardId: id,
                reviewedAt: now,
                grade: grade.name,
                quality: qualityOf(grade),
                intervalBefore: row.intervalDays,
                intervalAfter: next.intervalDays,
                easeBefore: row.easeFactor,
                easeAfter: next.easeFactor,
                deviceId: _db.deviceId,
                // De dónde partió, y lo necesario para deshacerlo (F31).
                phaseBefore: Value(before.phase),
                stepBefore: Value(row.learningStep),
                stepAfter: Value(next.learningStep),
                dueBefore: Value(row.dueAt),
                lastReviewedBefore: Value(row.lastReviewedAt),
                repetitionsBefore: Value(row.repetitions),
              ),
            );
        return next;
      });

      if (scheduled == null) {
        return left(
          const Failure.unexpected(
            message: 'La tarjeta ya no existe; puede que se haya borrado.',
          ),
        );
      }

      return right(scheduled);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(_unexpected(e, stackTrace, 'FlashcardRepositoryImpl.review'));
    }
  }

  @override
  Future<Either<Failure, Flashcard>> undoLastReview({DateTime? since}) async {
    try {
      // El estado de la tarjeta y el renglón del historial vuelven juntos: o
      // se deshace todo o no se toca nada.
      return await _db.transaction(() async {
        // La más reciente de este dispositivo. Si hay varias en el mismo
        // segundo, la última que se escribió (`rowid`): el orden en que
        // ocurrieron.
        final latest =
            await (_db.select(_db.reviewLogs)
                  ..where((r) {
                    final mine = r.deviceId.equals(_db.deviceId);
                    return since == null
                        ? mine
                        : mine & r.reviewedAt.isBiggerOrEqualValue(since);
                  })
                  ..orderBy([
                    (r) => OrderingTerm.desc(r.reviewedAt),
                    (r) =>
                        OrderingTerm.desc(const CustomExpression<int>('rowid')),
                  ])
                  ..limit(1))
                .getSingleOrNull();
        if (latest == null) {
          return left(
            const Failure.validation(
              message: 'No hay ninguna respuesta para deshacer.',
            ),
          );
        }
        final dueBefore = latest.dueBefore;
        if (dueBefore == null) {
          return left(
            const Failure.validation(
              message:
                  'Esa respuesta es de antes de que se guardara cómo estaba la '
                  'tarjeta: no se puede deshacer.',
            ),
          );
        }

        final card = await (_db.select(
          _db.flashcards,
        )..where((f) => f.id.equals(latest.flashcardId))).getSingleOrNull();
        if (card == null) {
          return left(
            const Failure.unexpected(
              message: 'La tarjeta ya no existe; puede que se haya borrado.',
            ),
          );
        }
        // Que sea la última respuesta de ESA tarjeta, y que la tarjeta siga
        // como la dejó: si no, restaurarla pisaría un repaso real.
        final newestOfCard =
            await (_db.select(_db.reviewLogs)
                  ..where((r) => r.flashcardId.equals(card.id))
                  ..orderBy([
                    (r) => OrderingTerm.desc(r.reviewedAt),
                    (r) =>
                        OrderingTerm.desc(const CustomExpression<int>('rowid')),
                  ])
                  ..limit(1))
                .getSingle();
        if (newestOfCard.id != latest.id ||
            card.lastReviewedAt != latest.reviewedAt) {
          return left(
            const Failure.validation(
              message:
                  'La tarjeta cambió después de esa respuesta: no se puede '
                  'deshacer sin pisar un repaso más nuevo.',
            ),
          );
        }

        await (_db.update(
          _db.flashcards,
        )..where((f) => f.id.equals(card.id))).write(
          FlashcardsCompanion(
            easeFactor: Value(latest.easeBefore),
            intervalDays: Value(latest.intervalBefore),
            repetitions: Value(latest.repetitionsBefore ?? card.repetitions),
            learningStep: Value(latest.stepBefore),
            dueAt: Value(dueBefore),
            lastReviewedAt: Value(latest.lastReviewedBefore),
          ),
        );
        await (_db.delete(
          _db.reviewLogs,
        )..where((r) => r.id.equals(latest.id))).go();

        final restored = await (_db.select(
          _db.flashcards,
        )..where((f) => f.id.equals(card.id))).getSingle();
        return right(_toEntity(restored));
      });
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'FlashcardRepositoryImpl.undoLastReview'),
      );
    }
  }

  @override
  Future<Either<Failure, Unit>> suspend(Iterable<String> ids) => _write(
    ids,
    'FlashcardRepositoryImpl.suspend',
    const FlashcardsCompanion(suspended: Value(true)),
  );

  @override
  Future<Either<Failure, Unit>> unsuspend(Iterable<String> ids) => _write(
    ids,
    'FlashcardRepositoryImpl.unsuspend',
    const FlashcardsCompanion(suspended: Value(false)),
  );

  @override
  Future<Either<Failure, Unit>> buryUntilTomorrow(Iterable<String> ids) =>
      _write(
        ids,
        'FlashcardRepositoryImpl.buryUntilTomorrow',
        FlashcardsCompanion(buriedUntil: Value(_day.endOf(_clock()))),
      );

  @override
  Future<Either<Failure, Unit>> unbury(Iterable<String> ids) => _write(
    ids,
    'FlashcardRepositoryImpl.unbury',
    const FlashcardsCompanion(buriedUntil: Value(null)),
  );

  /// Escribe [values] en las tarjetas [ids], de una vez: pausar cien tarjetas
  /// es una sola escritura y un solo aviso a quien mira.
  Future<Either<Failure, Unit>> _write(
    Iterable<String> ids,
    String hint,
    FlashcardsCompanion values,
  ) async {
    final wanted = ids.toSet();
    if (wanted.isEmpty) return right(unit);
    try {
      await (_db.update(
        _db.flashcards,
      )..where((f) => f.id.isIn(wanted))).write(values);
      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(_unexpected(e, stackTrace, hint));
    }
  }

  @override
  Stream<List<Flashcard>> watchForItem(String itemId) {
    return watchQuery(
      db: _db,
      tables: [_db.flashcards],
      read: () async {
        final rows =
            await (_db.select(_db.flashcards)
                  ..where((f) => f.itemId.equals(itemId))
                  ..orderBy([(f) => OrderingTerm(expression: f.createdAt)]))
                .get();
        return rows.map(_toEntity).toList();
      },
      telemetry: _telemetry,
      hint: 'FlashcardRepositoryImpl.watchForItem',
    );
  }

  @override
  Future<Either<Failure, List<Flashcard>>> getAll() async {
    try {
      final rows =
          await (_db.select(_db.flashcards)
                ..where((f) => itemIsActive(_db, f.itemId))
                ..orderBy([(f) => OrderingTerm(expression: f.createdAt)]))
              .get();
      return right(rows.map(_toEntity).toList());
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(_unexpected(e, stackTrace, 'FlashcardRepositoryImpl.getAll'));
    }
  }

  @override
  Future<Either<Failure, List<Flashcard>>> getPendingExport() async {
    try {
      final rows =
          await (_db.select(_db.flashcards)
                ..where(
                  (f) =>
                      f.lastExportedAt.isNull() & itemIsActive(_db, f.itemId),
                )
                ..orderBy([(f) => OrderingTerm(expression: f.createdAt)]))
              .get();
      return right(rows.map(_toEntity).toList());
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'FlashcardRepositoryImpl.getPendingExport'),
      );
    }
  }

  @override
  Future<Either<Failure, Unit>> markExported(Set<String> ids) async {
    if (ids.isEmpty) return right(unit);
    try {
      await (_db.update(_db.flashcards)..where((f) => f.id.isIn(ids))).write(
        FlashcardsCompanion(lastExportedAt: Value(_clock())),
      );
      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'FlashcardRepositoryImpl.markExported'),
      );
    }
  }

  /// El chunk de [itemId] que contiene la posición [offset], o `null` si el
  /// elemento no tiene chunks o [offset] cae fuera de todos.
  ///
  /// Un rango que cruza varios chunks se anota en el primero: el chunk es una
  /// ayuda para ubicar, y el que sirve es el rango.
  Future<String?> _chunkContaining(String itemId, int offset) async {
    final row =
        await (_db.select(_db.chunks)
              ..where(
                (c) =>
                    c.itemId.equals(itemId) &
                    c.charStart.isSmallerOrEqualValue(offset) &
                    c.charEnd.isBiggerThanValue(offset),
              )
              ..orderBy([(c) => OrderingTerm(expression: c.seq)])
              ..limit(1))
            .getSingleOrNull();
    return row?.id;
  }

  Flashcard _toEntity(FlashcardRow row) => flashcardFromRow(row);

  FlashcardOption _toOptionEntity(FlashcardOptionRow row) => FlashcardOption(
    id: row.id,
    flashcardId: row.flashcardId,
    content: row.content,
    isCorrect: row.isCorrect,
    position: row.position,
    sourceChunkId: row.sourceChunkId,
    sourceCharStart: row.sourceCharStart,
    sourceCharEnd: row.sourceCharEnd,
    sourceItemId: row.sourceItemId,
  );

  /// Catch-all deliberado, igual que en el resto de los repositorios: un
  /// `TypeError` es `Error`, no `Exception`, y atrapar solo `Exception` lo
  /// dejaría escapar dejando a quien llamó esperando una respuesta que
  /// nunca llega.
  Failure _unexpected(Object e, StackTrace stackTrace, String hint) {
    _telemetry.recordError(e, stackTrace, hint: hint);
    return Failure.unexpected(message: e.toString());
  }
}

/// Una hermana del grupo que falló al crearse: sale de la transacción para
/// deshacerlas todas.
class _SiblingFailed implements Exception {
  const _SiblingFailed(this.failure);

  final Failure failure;
}

/// Lo que se borra con una tarjeta de la IA al decir que «no era» (F27): la
/// fila y lo que se va con ella en cascada. Lo lleva el comprobante, y solo
/// este repositorio lo lee.
class _RemovedFlashcard {
  const _RemovedFlashcard({
    required this.card,
    required this.options,
    required this.reviews,
  });

  final FlashcardRow card;
  final List<FlashcardOptionRow> options;
  final List<ReviewLogRow> reviews;
}
