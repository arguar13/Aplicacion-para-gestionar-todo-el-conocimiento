import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/ai_rejection_memory.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/ai_rejection_kind.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/correction_subject.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/domain/entities/suggestion_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/core/domain/services/ai_rejection_fingerprint.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/util/id_generator.dart';

/// Las correcciones que propone un modelo al revisar lo que hizo la IA (F33,
/// «Revisar con otro modelo»), en la cola de sugerencias: crearlas, aplicarlas
/// al aceptarlas, deshacerlas con su pasada y contarlas.
///
/// Vive en la capa de base, como `atlas_suggestions.dart`, porque la usan dos
/// repositorios —el de las sugerencias, que las crea y las acepta, y el de las
/// pasadas, que las deshace y las cuenta— y la forma del `payload_json` tiene
/// que ser una sola.
///
/// Sin esquema nuevo: `correction` es un valor de `SuggestionKind` en una
/// columna de texto, y lo que no tiene columna —qué corrige, el antes y el
/// después, la pasada de revisión— va en el `payload_json`. La sugerencia
/// aceptada es también el registro de lo que se aplicó: con ella se deshace,
/// igual que la ubicación de un tema que la IA hizo sola.
///
/// Solo toca lo que sigue siendo de la IA **y está como el modelo lo vio**: si
/// la persona editó la tarjeta, ya es suya; si cambió de otro modo, la
/// corrección se hizo sobre algo que ya no está. En los dos casos no se
/// aplica, y deshacer tampoco pisa lo que la persona cambió después.

const _subjectKey = 'subject';
const _subjectIdKey = 'subjectId';
const _beforeKey = 'before';
const _afterKey = 'after';
const _reasonKey = 'reason';
const _modelKey = 'model';

/// La pasada de revisión que la propuso: aceptarla aplica el cambio dentro de
/// ella, y deshacerla lo devuelve a como estaba.
const _aiRunIdKey = 'aiRunId';

/// Se aplicó alguna vez —se aceptó—: cuenta en lo que hizo la pasada aunque
/// después se haya deshecho.
const _appliedKey = 'applied';

/// Lo que se borró al sacar una tarjeta —ella, sus opciones y sus repasos—,
/// para devolverla entera al deshacer.
const _removedKey = 'removed';

/// El «no era» que recordó la aceptación, si lo recordó ella —no si ya
/// estaba—: deshacer olvida solo ese.
const _rejectionIdKey = 'rejectionId';

const _cardKey = 'card';
const _optionsKey = 'options';
const _reviewsKey = 'reviews';

/// El `payload_json` de una corrección nueva, todavía sin aplicar.
String encodeCorrectionPayload({
  required CorrectionSubject subject,
  required String subjectId,
  required Map<String, String> before,
  required Map<String, String>? after,
  required String reason,
  required String aiRunId,
  String? model,
}) => jsonEncode({
  _subjectKey: subject.name,
  _subjectIdKey: subjectId,
  _beforeKey: before,
  _afterKey: ?after,
  _reasonKey: reason,
  _aiRunIdKey: aiRunId,
  _modelKey: ?model,
});

/// La sugerencia `correction` de [row].
CorrectionSuggestion correctionSuggestionOf(SuggestionRow row) {
  final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
  final after = payload[_afterKey] as Map<String, dynamic>?;
  return Suggestion.correction(
        id: row.id,
        targetItemId: row.targetItemId,
        subject: CorrectionSubject.values.byName(
          payload[_subjectKey] as String,
        ),
        subjectId: payload[_subjectIdKey] as String,
        before: _texts(payload[_beforeKey] as Map<String, dynamic>),
        after: after == null ? null : _texts(after),
        reason: payload[_reasonKey] as String,
        aiRunId: payload[_aiRunIdKey] as String,
        model: payload[_modelKey] as String?,
        confidence: row.confidence,
        status: row.status,
        createdAt: row.createdAt,
      )
      as CorrectionSuggestion;
}

Map<String, String> _texts(Map<String, dynamic> raw) => {
  for (final MapEntry(:key, :value) in raw.entries) key: value as String,
};

/// Aplica la corrección pendiente [row]: corrige la tarjeta o la saca, dentro
/// de su pasada de revisión, y anota en la sugerencia lo que hace falta para
/// deshacerlo. No cambia su estado: eso lo hace quien acepta.
///
/// Falla sin tocar nada si lo corregido ya no es de la IA o cambió desde que
/// el modelo lo vio.
///
/// Corre en la transacción de quien llama.
Future<Either<Failure, Unit>> applyCorrection(
  AppDatabase db,
  SuggestionRow row, {
  required IdGenerator ids,
  required DateTime now,
}) async {
  final correction = correctionSuggestionOf(row);
  final marks = switch (correction.subject) {
    CorrectionSubject.flashcard => await _applyToFlashcard(
      db,
      correction,
      ids: ids,
      now: now,
    ),
  };
  switch (marks) {
    case Left(:final value):
      return left(value);
    case Right(:final value):
      final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
      await (db.update(
        db.suggestions,
      )..where((s) => s.id.equals(row.id))).write(
        SuggestionsCompanion(
          payloadJson: Value(
            jsonEncode({...payload, ...value, _appliedKey: true}),
          ),
        ),
      );
      return right(unit);
  }
}

/// Las correcciones que la pasada de revisión [runId] aplicó y siguen en pie,
/// devueltas a como estaban: la tarjeta corregida vuelve a su texto de antes
/// —si sigue como la dejó la corrección— y la que se sacó vuelve entera —si
/// la pasada que la había hecho no se deshizo—. Devuelve cuántas volvieron.
///
/// En los dos casos el registro queda `rejected`: la persona no quiere esa
/// corrección, y una revisión nueva no la vuelve a proponer.
///
/// Corre en la transacción de quien llama —`AiRunRepositoryImpl.undoRun`—: o
/// se deshace la pasada entera, o nada.
Future<int> undoAiCorrections(AppDatabase db, String runId) async {
  var restored = 0;
  for (final row in await _appliedOf(db, [runId])) {
    if (await _undo(db, row)) restored++;
    await (db.update(db.suggestions)..where((s) => s.id.equals(row.id))).write(
      const SuggestionsCompanion(status: Value(SuggestionStatus.rejected)),
    );
  }
  return restored;
}

/// Cuántas correcciones aplicó cada una de [runIds]: las que se aceptaron
/// —`created`, la historia, se hayan deshecho o no— y las que todavía están
/// —`remaining`: siguen aceptadas, y lo corregido sigue como lo dejaron—. Una
/// pasada sin correcciones aplicadas no está.
///
/// Una que la persona cambió después —editó la tarjeta corregida, volvió a
/// crear la que se sacó— ya es suya, como un vínculo adoptado.
Future<Map<String, ({int created, int remaining})>> aiCorrectionCounts(
  AppDatabase db,
  Iterable<String> runIds,
) async {
  final rows = await _appliedOf(db, runIds);
  if (rows.isEmpty) return const {};
  final cards = await _cardsById(db, [
    for (final row in rows) correctionSuggestionOf(row).subjectId,
  ]);
  final alive = await _aliveRuns(db, rows.map(_removedRunOf).nonNulls);

  final counts = <String, ({int created, int remaining})>{};
  for (final row in rows) {
    final correction = correctionSuggestionOf(row);
    final removedFrom = _removedRunOf(row);
    final still =
        correction.status == SuggestionStatus.accepted &&
        _stillApplied(
          correction,
          cards[correction.subjectId],
          madeByLiveRun: removedFrom == null || alive.contains(removedFrom),
        );
    final was = counts[correction.aiRunId] ?? (created: 0, remaining: 0);
    counts[correction.aiRunId] = (
      created: was.created + 1,
      remaining: was.remaining + (still ? 1 : 0),
    );
  }
  return counts;
}

/// Las correcciones que se aplicaron alguna vez en [runIds], en cualquier
/// estado: aceptadas, o deshechas después. La pasada vive dentro del JSON,
/// como en `undoAiTopicPlacements`: son pocas filas por pasada.
Future<List<SuggestionRow>> _appliedOf(
  AppDatabase db,
  Iterable<String> runIds,
) async {
  final ids = runIds.toSet();
  if (ids.isEmpty) return const [];
  return (db.select(db.suggestions)
        ..where(
          (s) =>
              s.kind.equalsValue(SuggestionKind.correction) &
              _payloadField(_aiRunIdKey).isIn(ids) &
              _appliedField.equals(1),
        )
        ..orderBy([(s) => OrderingTerm.asc(s.createdAt)]))
      .get();
}

/// Un campo del `payload_json` de una sugerencia, leído en SQL.
Expression<String> _payloadField(String key) =>
    CustomExpression<String>("json_extract(payload_json, '\$.$key')");

/// Si se aplicó: un `true` de JSON se lee como el entero `1`, que no es igual
/// al texto `'1'`.
const _appliedField = CustomExpression<int>(
  "json_extract(payload_json, '\$.$_appliedKey')",
);

Future<Map<String, FlashcardRow>> _cardsById(
  AppDatabase db,
  Iterable<String> ids,
) async {
  final wanted = ids.toSet();
  if (wanted.isEmpty) return const {};
  final rows = await (db.select(
    db.flashcards,
  )..where((f) => f.id.isIn(wanted))).get();
  return {for (final row in rows) row.id: row};
}

/// Si lo que dejó [correction] sigue ahí: la tarjeta con el texto corregido y
/// todavía de la IA, o ya sin la tarjeta que se sacó —y con la pasada que la
/// había hecho en pie ([madeByLiveRun]): si esa se deshizo, la tarjeta se
/// habría ido igual, y sacarla ya no es obra de la revisión—.
bool _stillApplied(
  CorrectionSuggestion correction,
  FlashcardRow? card, {
  required bool madeByLiveRun,
}) {
  final after = correction.after;
  if (after == null) return card == null && madeByLiveRun;
  return card != null && _isAi(card) && _matches(card, after);
}

/// La pasada que había hecho la tarjeta que sacó la corrección [row]; `null`
/// si no sacó ninguna.
String? _removedRunOf(SuggestionRow row) {
  final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
  final removed = payload[_removedKey] as Map<String, dynamic>?;
  final card = removed?[_cardKey] as Map<String, dynamic>?;
  return card?['aiRunId'] as String?;
}

/// De [runIds], las pasadas que existen y no se deshicieron.
Future<Set<String>> _aliveRuns(AppDatabase db, Iterable<String> runIds) async {
  final ids = runIds.toSet();
  if (ids.isEmpty) return const {};
  final rows = await (db.select(
    db.aiRuns,
  )..where((r) => r.id.isIn(ids) & r.undoneAt.isNull())).get();
  return {for (final row in rows) row.id};
}

bool _isAi(FlashcardRow card) =>
    card.origin == ContentOrigin.ai && card.aiRunId != null;

bool _matches(FlashcardRow card, Map<String, String> texts) =>
    card.front == texts[FlashcardCorrectionField.front] &&
    card.back == texts[FlashcardCorrectionField.back];

/// Corrige o saca la tarjeta de [correction]. Devuelve lo que hay que anotar
/// en la sugerencia para deshacerlo.
Future<Either<Failure, Map<String, Object>>> _applyToFlashcard(
  AppDatabase db,
  CorrectionSuggestion correction, {
  required IdGenerator ids,
  required DateTime now,
}) async {
  final card = await (db.select(
    db.flashcards,
  )..where((f) => f.id.equals(correction.subjectId))).getSingleOrNull();
  if (card == null) {
    return left(
      const Failure.validation(
        message: 'Esa tarjeta ya no está: puede que la hayas borrado.',
      ),
    );
  }
  if (!_isAi(card)) {
    return left(
      const Failure.validation(
        message:
            'Esa tarjeta ya es tuya —la editaste—: la revisión no la toca.',
      ),
    );
  }
  if (!_matches(card, correction.before)) {
    return left(
      const Failure.validation(
        message:
            'La tarjeta cambió desde que se revisó: esta corrección ya no '
            'vale.',
      ),
    );
  }

  final after = correction.after;
  if (after != null) {
    final front = after[FlashcardCorrectionField.front]!.trim();
    final back = after[FlashcardCorrectionField.back]!.trim();
    if (front.isEmpty || back.isEmpty) {
      return left(
        const Failure.validation(
          message:
              'La corrección deja la tarjeta sin pregunta o sin respuesta.',
        ),
      );
    }
    if (card.kind != FlashcardKind.freeRecall) {
      return left(
        const Failure.validation(
          message: 'Solo se corrigen las tarjetas de pregunta y respuesta.',
        ),
      );
    }
    // Sigue siendo de la IA, de la pasada que la hizo: no es la persona
    // quien la edita. Si se deshace esa pasada, se va como cualquiera de ella.
    await (db.update(db.flashcards)..where((f) => f.id.equals(card.id))).write(
      FlashcardsCompanion(front: Value(front), back: Value(back)),
    );
    // La pregunta de antes estaba mal: que la IA no la vuelva a hacer. Si es la
    // misma —solo cambió la respuesta—, la tarjeta corregida ya la tiene.
    final rejection =
        flashcardRejectionFingerprint(card.front) ==
            flashcardRejectionFingerprint(front)
        ? null
        : await _rememberQuestion(db, card, ids: ids, now: now);
    return right({_afterKey: after, _rejectionIdKey: ?rejection});
  }

  // Sacarla es decir que «no era»: se recuerda su pregunta, y se guarda todo
  // lo que se va con ella en cascada para devolverla entera al deshacer.
  final removed = {
    _cardKey: card.toJson(),
    _optionsKey: [
      for (final option in await (db.select(
        db.flashcardOptions,
      )..where((o) => o.flashcardId.equals(card.id))).get())
        option.toJson(),
    ],
    _reviewsKey: [
      for (final review in await (db.select(
        db.reviewLogs,
      )..where((r) => r.flashcardId.equals(card.id))).get())
        review.toJson(),
    ],
  };
  final rejection = await _rememberQuestion(db, card, ids: ids, now: now);
  await (db.delete(db.flashcards)..where((f) => f.id.equals(card.id))).go();
  return right({_removedKey: removed, _rejectionIdKey: ?rejection});
}

/// Recuerda que la pregunta de [card] «no era» y devuelve el id de lo que
/// recordó; `null` si ya estaba recordada —entonces no es de esta corrección,
/// y deshacerla no la olvida—.
Future<String?> _rememberQuestion(
  AppDatabase db,
  FlashcardRow card, {
  required IdGenerator ids,
  required DateTime now,
}) async {
  final fingerprint = flashcardRejectionFingerprint(card.front);
  if (await isAiRejected(
    db,
    kind: AiRejectionKind.flashcard,
    itemId: card.itemId,
    fingerprint: fingerprint,
  )) {
    return null;
  }
  return rememberAiRejection(
    db,
    ids: ids,
    now: now,
    kind: AiRejectionKind.flashcard,
    itemId: card.itemId,
    fingerprint: fingerprint,
    subjectId: card.id,
  );
}

/// Devuelve a como estaba lo que aplicó la corrección [row], si sigue como
/// ella lo dejó. Devuelve si lo devolvió.
Future<bool> _undo(AppDatabase db, SuggestionRow row) async {
  final correction = correctionSuggestionOf(row);
  if (correction.status != SuggestionStatus.accepted) return false;
  final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
  final rejection = payload[_rejectionIdKey] as String?;
  final card = (await _cardsById(db, [
    correction.subjectId,
  ]))[correction.subjectId];
  final removedFrom = _removedRunOf(row);
  final madeByLiveRun =
      removedFrom == null ||
      (await _aliveRuns(db, [removedFrom])).contains(removedFrom);
  if (!_stillApplied(correction, card, madeByLiveRun: madeByLiveRun)) {
    return false;
  }

  if (correction.after != null) {
    await (db.update(db.flashcards)..where((f) => f.id.equals(card!.id))).write(
      FlashcardsCompanion(
        front: Value(correction.before[FlashcardCorrectionField.front]!),
        back: Value(correction.before[FlashcardCorrectionField.back]!),
      ),
    );
  } else {
    final removed = payload[_removedKey] as Map<String, dynamic>;
    final restored = FlashcardRow.fromJson(
      removed[_cardKey] as Map<String, dynamic>,
    );
    await db
        .into(db.flashcards)
        .insert(restored, mode: InsertMode.insertOrIgnore);
    for (final option in removed[_optionsKey] as List<dynamic>) {
      await db
          .into(db.flashcardOptions)
          .insert(
            FlashcardOptionRow.fromJson(option as Map<String, dynamic>),
            mode: InsertMode.insertOrIgnore,
          );
    }
    for (final review in removed[_reviewsKey] as List<dynamic>) {
      await db
          .into(db.reviewLogs)
          .insert(
            ReviewLogRow.fromJson(review as Map<String, dynamic>),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }
  if (rejection != null) await forgetAiRejection(db, rejection);
  return true;
}
