import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/ai_rejection_memory.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/ai_rejection_kind.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/correction_subject.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
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
/// la persona lo editó, ya es suyo; si cambió de otro modo, la corrección se
/// hizo sobre algo que ya no está. En los dos casos no se aplica, y deshacer
/// tampoco pisa lo que la persona cambió después.
///
/// Cada cosa que se corrige ([CorrectionSubject]) sabe leerse, decir si sigue
/// así, cambiarse y volver: ver [_Target].

const _subjectKey = 'subject';
const _subjectIdKey = 'subjectId';
const _beforeKey = 'before';
const _afterKey = 'after';
const _reasonKey = 'reason';
const _modelKey = 'model';
const _labelKey = 'label';

/// La pasada de revisión que la propuso: aceptarla aplica el cambio dentro de
/// ella, y deshacerla lo devuelve a como estaba.
const _aiRunIdKey = 'aiRunId';

/// Se aplicó alguna vez —se aceptó—: cuenta en lo que hizo la pasada aunque
/// después se haya deshecho.
const _appliedKey = 'applied';

/// Lo que se borró al sacarlo, para devolverlo entero al deshacer: la
/// tarjeta con sus opciones y sus repasos, o el vínculo.
const _removedKey = 'removed';

/// El «no era» que recordó la aceptación, si lo recordó ella —no si ya
/// estaba—: deshacer olvida solo ese.
const _rejectionIdKey = 'rejectionId';

const _cardKey = 'card';
const _optionsKey = 'options';
const _reviewsKey = 'reviews';
const _relationKey = 'relation';

/// El `payload_json` de una corrección nueva, todavía sin aplicar.
String encodeCorrectionPayload({
  required CorrectionSubject subject,
  required String subjectId,
  required Map<String, String> before,
  required Map<String, String>? after,
  required String reason,
  required String aiRunId,
  String? model,
  String? label,
}) => jsonEncode({
  _subjectKey: subject.name,
  _subjectIdKey: subjectId,
  _beforeKey: before,
  _afterKey: ?after,
  _reasonKey: reason,
  _aiRunIdKey: aiRunId,
  _modelKey: ?model,
  _labelKey: ?label,
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
        label: payload[_labelKey] as String?,
        confidence: row.confidence,
        status: row.status,
        createdAt: row.createdAt,
      )
      as CorrectionSuggestion;
}

Map<String, String> _texts(Map<String, dynamic> raw) => {
  for (final MapEntry(:key, :value) in raw.entries) key: value as String,
};

/// De [corrections], las que todavía se pueden aplicar: lo corregido sigue
/// siendo de la IA y está como el modelo lo vio. Las demás se hicieron sobre
/// algo que ya no está —la persona lo editó, lo borró, o cambió de otro
/// modo— y no tiene sentido ofrecerlas: aceptarlas fallaría.
Future<List<CorrectionSuggestion>> stillApplicableCorrections(
  AppDatabase db,
  List<CorrectionSuggestion> corrections,
) async {
  if (corrections.isEmpty) return const [];
  final rows = await _rowsOf(db, corrections);
  return [
    for (final correction in corrections)
      if (rows[(correction.subject, correction.subjectId)] case final row?
          when _targetOf(correction.subject).isAi(row) &&
              _targetOf(correction.subject).matches(row, correction.before))
        correction,
  ];
}

/// Aplica la corrección pendiente [row]: corrige lo corregido o lo saca,
/// dentro de su pasada de revisión, y anota en la sugerencia lo que hace
/// falta para deshacerlo. No cambia su estado: eso lo hace quien acepta.
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
  final target = _targetOf(correction.subject);
  final current = (await target.rowsById(db, {
    correction.subjectId,
  }))[correction.subjectId];
  if (current == null) return left(Failure.validation(message: target.missing));
  if (!target.isAi(current)) {
    return left(Failure.validation(message: target.adopted));
  }
  if (!target.matches(current, correction.before)) {
    return left(Failure.validation(message: target.changed));
  }

  final marks = await target.apply(db, current, correction, ids: ids, now: now);
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
/// devueltas a como estaban: lo corregido vuelve a como era —si sigue como lo
/// dejó la corrección— y lo que se sacó vuelve entero —si la pasada que lo
/// había hecho no se deshizo—. Devuelve cuántas volvieron.
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
/// Una que la persona cambió después —editó lo corregido, volvió a crear lo
/// que se sacó— ya es suya, como un vínculo adoptado.
Future<Map<String, ({int created, int remaining})>> aiCorrectionCounts(
  AppDatabase db,
  Iterable<String> runIds,
) async {
  final rows = await _appliedOf(db, runIds);
  if (rows.isEmpty) return const {};
  final corrections = [for (final row in rows) correctionSuggestionOf(row)];
  final current = await _rowsOf(db, corrections);
  final alive = await _aliveRuns(db, rows.map(_removedRunOf).nonNulls);

  final counts = <String, ({int created, int remaining})>{};
  for (final (index, row) in rows.indexed) {
    final correction = corrections[index];
    final removedFrom = _removedRunOf(row);
    final still =
        correction.status == SuggestionStatus.accepted &&
        _stillApplied(
          correction,
          current[(correction.subject, correction.subjectId)],
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

/// Lo corregido por cada una de [corrections], como está hoy, por qué es y
/// cuál; lo que ya no está, no.
Future<Map<(CorrectionSubject, String), Object>> _rowsOf(
  AppDatabase db,
  Iterable<CorrectionSuggestion> corrections,
) async {
  final wanted = <CorrectionSubject, Set<String>>{};
  for (final correction in corrections) {
    (wanted[correction.subject] ??= {}).add(correction.subjectId);
  }
  return {
    for (final MapEntry(key: subject, value: ids) in wanted.entries)
      for (final MapEntry(:key, :value) in (await _targetOf(
        subject,
      ).rowsById(db, ids)).entries)
        (subject, key): value,
  };
}

/// Si lo que dejó [correction] sigue ahí: lo corregido con el valor de la
/// corrección y todavía de la IA, o ya sin lo que se sacó —y con la pasada
/// que lo había hecho en pie ([madeByLiveRun]): si esa se deshizo, se habría
/// ido igual, y sacarlo ya no es obra de la revisión—.
bool _stillApplied(
  CorrectionSuggestion correction,
  Object? current, {
  required bool madeByLiveRun,
}) {
  final after = correction.after;
  if (after == null) return current == null && madeByLiveRun;
  final target = _targetOf(correction.subject);
  return current != null &&
      target.isAi(current) &&
      target.matches(current, after);
}

/// La pasada que había hecho lo que sacó la corrección [row]; `null` si no
/// sacó nada.
String? _removedRunOf(SuggestionRow row) {
  final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
  final removed = payload[_removedKey] as Map<String, dynamic>?;
  if (removed == null) return null;
  return _targetOf(
    CorrectionSubject.values.byName(payload[_subjectKey] as String),
  ).removedRunOf(removed);
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

/// Devuelve a como estaba lo que aplicó la corrección [row], si sigue como
/// ella lo dejó. Devuelve si lo devolvió.
Future<bool> _undo(AppDatabase db, SuggestionRow row) async {
  final correction = correctionSuggestionOf(row);
  if (correction.status != SuggestionStatus.accepted) return false;
  final target = _targetOf(correction.subject);
  final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
  final current = (await target.rowsById(db, {
    correction.subjectId,
  }))[correction.subjectId];
  final removedFrom = _removedRunOf(row);
  final madeByLiveRun =
      removedFrom == null ||
      (await _aliveRuns(db, [removedFrom])).contains(removedFrom);
  if (!_stillApplied(correction, current, madeByLiveRun: madeByLiveRun)) {
    return false;
  }

  final restored = correction.after != null
      ? await target.restoreBefore(db, current!, correction)
      : await target.restoreRemoved(
          db,
          payload[_removedKey] as Map<String, dynamic>,
        );
  if (!restored) return false;
  if (payload[_rejectionIdKey] case final String rejection) {
    await forgetAiRejection(db, rejection);
  }
  return true;
}

/// Lo que cada cosa que se corrige sabe hacer: leerse, decir si sigue siendo
/// de la IA y como la vio el modelo, cambiarse o sacarse, y volver.
abstract class _Target {
  const _Target();

  /// Lo que se dice al no poder aplicar: ya no está, ya es de la persona, o
  /// cambió desde que el modelo lo vio.
  String get missing;
  String get adopted;
  String get changed;

  /// Las filas de [ids] que siguen existiendo, por su id.
  Future<Map<String, Object>> rowsById(AppDatabase db, Set<String> ids);

  /// Si [row] sigue siendo de la IA —y de lo que se revisa—.
  bool isAi(Object row);

  /// Si [row] tiene los datos [fields] (el antes o el después).
  bool matches(Object row, Map<String, String> fields);

  /// Corrige o saca [row], que ya se sabe de la IA y como el modelo la vio.
  /// Devuelve lo que hay que anotar en la sugerencia —el después tal como
  /// quedó, lo sacado, el «no era» que recordó— o por qué no se puede.
  Future<Either<Failure, Map<String, Object>>> apply(
    AppDatabase db,
    Object row,
    CorrectionSuggestion correction, {
    required IdGenerator ids,
    required DateTime now,
  });

  /// Vuelve [row] al antes de [correction]. Devuelve si pudo.
  Future<bool> restoreBefore(
    AppDatabase db,
    Object row,
    CorrectionSuggestion correction,
  );

  /// Vuelve a poner lo que se sacó, guardado en [removed]. Devuelve si pudo.
  Future<bool> restoreRemoved(AppDatabase db, Map<String, dynamic> removed);

  /// La pasada que había hecho lo que se guardó en [removed].
  String? removedRunOf(Map<String, dynamic> removed);
}

_Target _targetOf(CorrectionSubject subject) => switch (subject) {
  CorrectionSubject.flashcard => const _FlashcardTarget(),
  CorrectionSubject.relation => const _RelationTarget(),
};

/// Una tarjeta de pregunta y respuesta: se corrige su texto o se saca, con
/// sus opciones y sus repasos.
class _FlashcardTarget extends _Target {
  const _FlashcardTarget();

  @override
  String get missing => 'Esa tarjeta ya no está: puede que la hayas borrado.';

  @override
  String get adopted =>
      'Esa tarjeta ya es tuya —la editaste—: la revisión no la toca.';

  @override
  String get changed =>
      'La tarjeta cambió desde que se revisó: esta corrección ya no vale.';

  @override
  Future<Map<String, Object>> rowsById(AppDatabase db, Set<String> ids) async {
    if (ids.isEmpty) return const {};
    final rows = await (db.select(
      db.flashcards,
    )..where((f) => f.id.isIn(ids))).get();
    return {for (final row in rows) row.id: row};
  }

  @override
  bool isAi(Object row) {
    final card = row as FlashcardRow;
    return card.origin == ContentOrigin.ai && card.aiRunId != null;
  }

  @override
  bool matches(Object row, Map<String, String> fields) {
    final card = row as FlashcardRow;
    return card.front == fields[FlashcardCorrectionField.front] &&
        card.back == fields[FlashcardCorrectionField.back];
  }

  @override
  Future<Either<Failure, Map<String, Object>>> apply(
    AppDatabase db,
    Object row,
    CorrectionSuggestion correction, {
    required IdGenerator ids,
    required DateTime now,
  }) async {
    final card = row as FlashcardRow;
    final after = correction.after;
    if (after != null) {
      final front = after[FlashcardCorrectionField.front]?.trim() ?? '';
      final back = after[FlashcardCorrectionField.back]?.trim() ?? '';
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
      // quien la edita. Si se deshace esa pasada, se va como cualquiera de
      // ella.
      await (db.update(db.flashcards)..where((f) => f.id.equals(card.id)))
          .write(FlashcardsCompanion(front: Value(front), back: Value(back)));
      // La pregunta de antes estaba mal: que la IA no la vuelva a hacer. Si es
      // la misma —solo cambió la respuesta—, la tarjeta corregida ya la tiene.
      final rejection =
          flashcardRejectionFingerprint(card.front) ==
              flashcardRejectionFingerprint(front)
          ? null
          : await _rememberQuestion(db, card, ids: ids, now: now);
      return right({
        // Como quedó: con eso se sabe después si sigue así.
        _afterKey: {
          FlashcardCorrectionField.front: front,
          FlashcardCorrectionField.back: back,
        },
        _rejectionIdKey: ?rejection,
      });
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

  @override
  Future<bool> restoreBefore(
    AppDatabase db,
    Object row,
    CorrectionSuggestion correction,
  ) async {
    final card = row as FlashcardRow;
    await (db.update(db.flashcards)..where((f) => f.id.equals(card.id))).write(
      FlashcardsCompanion(
        front: Value(correction.before[FlashcardCorrectionField.front]!),
        back: Value(correction.before[FlashcardCorrectionField.back]!),
      ),
    );
    return true;
  }

  @override
  Future<bool> restoreRemoved(
    AppDatabase db,
    Map<String, dynamic> removed,
  ) async {
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
    return true;
  }

  @override
  String? removedRunOf(Map<String, dynamic> removed) =>
      (removed[_cardKey] as Map<String, dynamic>?)?['aiRunId'] as String?;

  /// Recuerda que la pregunta de [card] «no era» y devuelve el id de lo que
  /// recordó; `null` si ya estaba recordada —entonces no es de esta
  /// corrección, y deshacerla no la olvida—.
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
}

/// Un vínculo de la IA que es una opinión sobre dos elementos: se corrige su
/// tipo y su frase, o se saca. La estructura —una extracción, un índice— no
/// se revisa: la pone el flujo que crea esa nota.
class _RelationTarget extends _Target {
  const _RelationTarget();

  @override
  String get missing => 'Ese vínculo ya no está: puede que lo hayas borrado.';

  @override
  String get adopted =>
      'Ese vínculo ya es tuyo —lo editaste—: la revisión no lo toca.';

  @override
  String get changed =>
      'El vínculo cambió desde que se revisó: esta corrección ya no vale.';

  @override
  Future<Map<String, Object>> rowsById(AppDatabase db, Set<String> ids) async {
    if (ids.isEmpty) return const {};
    final rows = await (db.select(
      db.relations,
    )..where((r) => r.id.isIn(ids))).get();
    return {for (final row in rows) row.id: row};
  }

  @override
  bool isAi(Object row) {
    final relation = row as RelationRow;
    return relation.origin == ContentOrigin.ai &&
        relation.aiRunId != null &&
        !relation.kind.isStructural;
  }

  @override
  bool matches(Object row, Map<String, String> fields) {
    final relation = row as RelationRow;
    return relation.kind.name == fields[RelationCorrectionField.kind] &&
        (relation.note ?? '') == fields[RelationCorrectionField.note];
  }

  @override
  Future<Either<Failure, Map<String, Object>>> apply(
    AppDatabase db,
    Object row,
    CorrectionSuggestion correction, {
    required IdGenerator ids,
    required DateTime now,
  }) async {
    final relation = row as RelationRow;
    final after = correction.after;
    if (after != null) {
      final kind = RelationKind.values
          .asNameMap()[after[RelationCorrectionField.kind]];
      if (kind == null || kind.isStructural) {
        return left(
          const Failure.validation(
            message: 'La corrección le pone al vínculo un tipo que no va.',
          ),
        );
      }
      final note = after[RelationCorrectionField.note]?.trim() ?? '';
      if (kind != relation.kind && await _twinOf(db, relation, kind) != null) {
        return left(
          const Failure.validation(
            message: 'Ya hay un vínculo de ese tipo entre los dos elementos.',
          ),
        );
      }
      // Sigue siendo de la IA, de la pasada que lo hizo, como una tarjeta
      // corregida.
      await (db.update(
        db.relations,
      )..where((r) => r.id.equals(relation.id))).write(
        RelationsCompanion(
          kind: Value(kind),
          note: Value(note.isEmpty ? null : note),
        ),
      );
      // El tipo de antes estaba mal: que la IA no lo vuelva a proponer.
      final rejection = kind == relation.kind
          ? null
          : await _rememberRelation(db, relation, ids: ids, now: now);
      return right({
        _afterKey: {
          RelationCorrectionField.kind: kind.name,
          RelationCorrectionField.note: note,
        },
        _rejectionIdKey: ?rejection,
      });
    }

    final rejection = await _rememberRelation(db, relation, ids: ids, now: now);
    await (db.delete(
      db.relations,
    )..where((r) => r.id.equals(relation.id))).go();
    return right({
      _removedKey: {_relationKey: relation.toJson()},
      _rejectionIdKey: ?rejection,
    });
  }

  @override
  Future<bool> restoreBefore(
    AppDatabase db,
    Object row,
    CorrectionSuggestion correction,
  ) async {
    final relation = row as RelationRow;
    final kind = RelationKind.values.byName(
      correction.before[RelationCorrectionField.kind]!,
    );
    // Si mientras tanto alguien hizo el vínculo de antes, ya está: no se
    // puede tener dos iguales.
    if (kind != relation.kind && await _twinOf(db, relation, kind) != null) {
      return false;
    }
    final note = correction.before[RelationCorrectionField.note]!;
    await (db.update(
      db.relations,
    )..where((r) => r.id.equals(relation.id))).write(
      RelationsCompanion(
        kind: Value(kind),
        note: Value(note.isEmpty ? null : note),
      ),
    );
    return true;
  }

  @override
  Future<bool> restoreRemoved(
    AppDatabase db,
    Map<String, dynamic> removed,
  ) async {
    final relation = RelationRow.fromJson(
      removed[_relationKey] as Map<String, dynamic>,
    );
    if (await _twinOf(db, relation, relation.kind) != null) return false;
    // Los dos elementos tienen que seguir existiendo —en la papelera también
    // cuentan—: un vínculo a algo que se borró del todo no vuelve.
    final ends = await (db.select(
      db.knowledgeEntries,
    )..where((e) => e.id.isIn([relation.fromItemId, relation.toItemId]))).get();
    if (ends.length < 2) return false;
    await db.into(db.relations).insert(relation);
    return true;
  }

  @override
  String? removedRunOf(Map<String, dynamic> removed) =>
      (removed[_relationKey] as Map<String, dynamic>?)?['aiRunId'] as String?;

  /// El vínculo de [kind] entre los mismos dos elementos que [relation], en
  /// el mismo sentido, si hay. Quien pregunta lo hace por otro tipo que el de
  /// [relation], o por uno que ya no está: nunca lo encuentra a él.
  Future<RelationRow?> _twinOf(
    AppDatabase db,
    RelationRow relation,
    RelationKind kind,
  ) =>
      (db.select(db.relations)..where(
            (r) =>
                r.fromItemId.equals(relation.fromItemId) &
                r.toItemId.equals(relation.toItemId) &
                r.kind.equalsValue(kind),
          ))
          .getSingleOrNull();

  /// Recuerda que [relation], con su tipo de ahora, «no era»; `null` si ya
  /// estaba recordado.
  Future<String?> _rememberRelation(
    AppDatabase db,
    RelationRow relation, {
    required IdGenerator ids,
    required DateTime now,
  }) async {
    final key = relationRejectionKey(
      fromItemId: relation.fromItemId,
      toItemId: relation.toItemId,
      kind: relation.kind,
    );
    if (await isAiRejected(
      db,
      kind: AiRejectionKind.relation,
      itemId: key.itemId,
      fingerprint: key.fingerprint,
    )) {
      return null;
    }
    return rememberAiRejection(
      db,
      ids: ids,
      now: now,
      kind: AiRejectionKind.relation,
      itemId: key.itemId,
      otherItemId: key.otherItemId,
      fingerprint: key.fingerprint,
      subjectId: relation.id,
    );
  }
}
