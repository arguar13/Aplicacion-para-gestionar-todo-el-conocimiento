import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';

/// De la fila de la base a la tarjeta, en un solo lugar: lo usan el repositorio
/// de tarjetas y la cola de estudio, y una columna nueva se agrega acá.
Flashcard flashcardFromRow(FlashcardRow row) => Flashcard(
  id: row.id,
  itemId: row.itemId,
  front: row.front,
  back: row.back,
  dueAt: row.dueAt,
  createdAt: row.createdAt,
  easeFactor: row.easeFactor,
  intervalDays: row.intervalDays,
  repetitions: row.repetitions,
  lastReviewedAt: row.lastReviewedAt,
  kind: row.kind,
  sourceChunkId: row.sourceChunkId,
  sourceCharStart: row.sourceCharStart,
  sourceCharEnd: row.sourceCharEnd,
  lastExportedAt: row.lastExportedAt,
  origin: row.origin,
  aiRunId: row.aiRunId,
  suspended: row.suspended,
  buriedUntil: row.buriedUntil,
  learningStep: row.learningStep,
  groupId: row.groupId,
  clozeIndex: row.clozeIndex,
);
