import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/ai_field_values.dart';
import 'package:sinapsis/core/database/ai_rejection_memory.dart';
import 'package:sinapsis/core/database/ai_run_sql.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/database/reference_reader.dart';
import 'package:sinapsis/core/database/vocabulary_lookup.dart';
import 'package:sinapsis/core/domain/entities/ai_changed_field.dart';
import 'package:sinapsis/core/domain/entities/ai_rejection_kind.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/correction_subject.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/domain/entities/suggestion_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/core/domain/services/ai_rejection_fingerprint.dart';
import 'package:sinapsis/core/domain/services/reference_normalizer.dart';
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

/// Cuál es lo corregido después de aplicar, si cambió de identidad: una
/// propiedad corregida es otra fila, la del valor nuevo. Sin esto, es
/// `subjectId`.
const _appliedIdKey = 'appliedSubjectId';

const _cardKey = 'card';
const _optionsKey = 'options';
const _reviewsKey = 'reviews';
const _relationKey = 'relation';
const _propertyKey = 'property';
const _itemIdKey = 'itemId';
const _spaceIdKey = 'spaceId';
const _fieldKey = 'field';
const _valueKey = 'value';

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
  final rows = await _rowsOf(db, [
    for (final correction in corrections)
      (correction.subject, correction.subjectId),
  ]);
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
/// se deshace la pasada entera, o nada. [now] es la hora de lo que se
/// escribe en el elemento (el tema), que queda versionado.
Future<int> undoAiCorrections(
  AppDatabase db,
  String runId, {
  required DateTime now,
}) async {
  var restored = 0;
  for (final row in await _appliedOf(db, [runId])) {
    if (await _undo(db, row, now: now)) restored++;
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
  final keys = [for (final row in rows) _currentKeyOf(row)];
  final current = await _rowsOf(db, keys);
  final alive = await _aliveRuns(db, rows.map(_removedRunOf).nonNulls);

  final counts = <String, ({int created, int remaining})>{};
  for (final (index, row) in rows.indexed) {
    final correction = corrections[index];
    final removedFrom = _removedRunOf(row);
    final still =
        correction.status == SuggestionStatus.accepted &&
        _stillApplied(
          correction,
          current[keys[index]],
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

/// Cuál es hoy lo corregido por la corrección [row]: el de `subjectId`, o
/// el que quedó al aplicarla si cambió de identidad ([_appliedIdKey]).
(CorrectionSubject, String) _currentKeyOf(SuggestionRow row) {
  final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
  return (
    CorrectionSubject.values.byName(payload[_subjectKey] as String),
    (payload[_appliedIdKey] ?? payload[_subjectIdKey]) as String,
  );
}

/// Lo que hay hoy en cada una de [keys] —qué cosa es y cuál—; lo que ya no
/// está, no.
Future<Map<(CorrectionSubject, String), Object>> _rowsOf(
  AppDatabase db,
  Iterable<(CorrectionSubject, String)> keys,
) async {
  final wanted = <CorrectionSubject, Set<String>>{};
  for (final (subject, id) in keys) {
    (wanted[subject] ??= {}).add(id);
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
  final target = _targetOf(correction.subject);
  if (after == null) return target.isRemoved(current) && madeByLiveRun;
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
Future<bool> _undo(
  AppDatabase db,
  SuggestionRow row, {
  required DateTime now,
}) async {
  final correction = correctionSuggestionOf(row);
  if (correction.status != SuggestionStatus.accepted) return false;
  final target = _targetOf(correction.subject);
  final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
  final key = _currentKeyOf(row);
  final current = (await target.rowsById(db, {key.$2}))[key.$2];
  final removedFrom = _removedRunOf(row);
  final madeByLiveRun =
      removedFrom == null ||
      (await _aliveRuns(db, [removedFrom])).contains(removedFrom);
  if (!_stillApplied(correction, current, madeByLiveRun: madeByLiveRun)) {
    return false;
  }

  final restored = correction.after != null
      ? await target.restoreBefore(db, current!, correction, now: now)
      : await target.restoreRemoved(
          db,
          payload[_removedKey] as Map<String, dynamic>,
          now: now,
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

  /// Si lo que se sacó sigue sacado: lo de hoy es [current], `null` si ya no
  /// está. Casi siempre es eso, que no esté; el tema, en cambio, sigue
  /// teniendo su registro, y sacado es el elemento sin tema.
  bool isRemoved(Object? current) => current == null;

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
    CorrectionSuggestion correction, {
    required DateTime now,
  });

  /// Vuelve a poner lo que se sacó, guardado en [removed]. Devuelve si pudo.
  Future<bool> restoreRemoved(
    AppDatabase db,
    Map<String, dynamic> removed, {
    required DateTime now,
  });

  /// La pasada que había hecho lo que se guardó en [removed].
  String? removedRunOf(Map<String, dynamic> removed);
}

_Target _targetOf(CorrectionSubject subject) => switch (subject) {
  CorrectionSubject.flashcard => const _FlashcardTarget(),
  CorrectionSubject.relation => const _RelationTarget(),
  CorrectionSubject.property => const _PropertyTarget(),
  CorrectionSubject.space => const _SpaceTarget(),
  CorrectionSubject.reference => const _ReferenceTarget(),
  CorrectionSubject.mapIntro => const _MapIntroTarget(),
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
    CorrectionSuggestion correction, {
    required DateTime now,
  }) async {
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
    Map<String, dynamic> removed, {
    required DateTime now,
  }) async {
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
    CorrectionSuggestion correction, {
    required DateTime now,
  }) async {
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
    Map<String, dynamic> removed, {
    required DateTime now,
  }) async {
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

/// Una etiqueta o propiedad puesta por la IA, como está hoy: la asignación
/// con su valor y su categoría.
class _Assigned {
  const _Assigned({
    required this.row,
    required this.value,
    required this.definitionId,
    required this.definitionName,
    required this.type,
    required this.byMapNote,
  });

  final ItemPropertyValueRow row;
  final String value;
  final String definitionId;
  final String definitionName;
  final PropertyValueType type;

  /// La puso la pasada que creó una nota mapa: es el tema del que la nota es
  /// índice, parte de la nota, y no se revisa suelta.
  final bool byMapNote;
}

/// Una etiqueta o propiedad de la IA: se corrige por otro valor que ya esté
/// en su categoría, o se saca. Corregir es cambiar de fila —la asignación es
/// el par elemento y valor—, que sigue siendo de la IA y de su pasada.
class _PropertyTarget extends _Target {
  const _PropertyTarget();

  @override
  String get missing =>
      'Esa etiqueta ya no está en el elemento: puede que la hayas sacado.';

  @override
  String get adopted => 'Esa etiqueta ya es tuya: la revisión no la toca.';

  @override
  String get changed =>
      'La etiqueta cambió desde que se revisó: esta corrección ya no vale.';

  @override
  Future<Map<String, Object>> rowsById(AppDatabase db, Set<String> ids) async {
    final found = <String, Object>{};
    for (final id in ids) {
      final cut = id.indexOf('/');
      if (cut <= 0) continue;
      final itemId = id.substring(0, cut);
      final valueId = id.substring(cut + 1);
      final query =
          db.select(db.itemPropertyValues).join([
            innerJoin(
              db.propertyValues,
              db.propertyValues.id.equalsExp(
                db.itemPropertyValues.propertyValueId,
              ),
            ),
            innerJoin(
              db.propertyDefinitions,
              db.propertyDefinitions.id.equalsExp(
                db.propertyValues.definitionId,
              ),
            ),
          ])..where(
            db.itemPropertyValues.itemId.equals(itemId) &
                db.itemPropertyValues.propertyValueId.equals(valueId),
          );
      final joined = await query.getSingleOrNull();
      if (joined == null) continue;
      final row = joined.readTable(db.itemPropertyValues);
      final value = joined.readTable(db.propertyValues);
      final definition = joined.readTable(db.propertyDefinitions);
      final runId = row.aiRunId;
      final byMapNote =
          runId != null &&
          await (db.select(db.aiFieldChanges)..where(
                    (c) =>
                        c.aiRunId.equals(runId) &
                        c.field.equalsValue(AiChangedField.mapNote),
                  ))
                  .getSingleOrNull() !=
              null;
      found[id] = _Assigned(
        row: row,
        value: value.value,
        definitionId: definition.id,
        definitionName: definition.name,
        type: definition.type,
        byMapNote: byMapNote,
      );
    }
    return found;
  }

  // El origen dice si la puso la IA; su pasada puede faltar —si se borró,
  // `ai_run_id` queda en null— y sigue siendo de la IA igual.
  @override
  bool isAi(Object row) {
    final assigned = row as _Assigned;
    return assigned.row.origin == ItemPropertyOrigin.ai && !assigned.byMapNote;
  }

  @override
  bool matches(Object row, Map<String, String> fields) =>
      (row as _Assigned).value == fields[PropertyCorrectionField.value];

  @override
  Future<Either<Failure, Map<String, Object>>> apply(
    AppDatabase db,
    Object row,
    CorrectionSuggestion correction, {
    required IdGenerator ids,
    required DateTime now,
  }) async {
    final assigned = row as _Assigned;
    final after = correction.after;
    if (after != null) {
      if (assigned.type != PropertyValueType.text) {
        return left(
          const Failure.validation(
            message:
                'Solo se corrigen las etiquetas de texto: un número, una '
                'fecha o una persona se sacan o se editan a mano.',
          ),
        );
      }
      final wanted = after[PropertyCorrectionField.value]?.trim() ?? '';
      final target = wanted.isEmpty
          ? null
          : await findValueByLabelOrAlias(db, assigned.definitionId, wanted);
      if (target == null) {
        return left(
          Failure.validation(
            message:
                '«$wanted» no está en tu vocabulario de '
                '«${assigned.definitionName}»: la revisión no inventa '
                'valores.',
          ),
        );
      }
      if (target.id == assigned.row.propertyValueId) {
        return left(
          const Failure.validation(message: 'La corrección no cambia nada.'),
        );
      }
      if (await _assignment(db, assigned.row.itemId, target.id) != null) {
        return left(
          Failure.validation(
            message: 'El elemento ya tiene «${target.value}».',
          ),
        );
      }
      await _replace(db, assigned.row, withValueId: target.id);
      final rejection = await _rememberAssignment(
        db,
        assigned,
        ids: ids,
        now: now,
      );
      return right({
        _appliedIdKey: propertyCorrectionSubjectId(
          assigned.row.itemId,
          target.id,
        ),
        _afterKey: {
          PropertyCorrectionField.category: assigned.definitionName,
          PropertyCorrectionField.value: target.value,
        },
        _rejectionIdKey: ?rejection,
      });
    }

    final rejection = await _rememberAssignment(
      db,
      assigned,
      ids: ids,
      now: now,
    );
    await _delete(db, assigned.row);
    return right({
      _removedKey: {_propertyKey: assigned.row.toJson()},
      _rejectionIdKey: ?rejection,
    });
  }

  @override
  Future<bool> restoreBefore(
    AppDatabase db,
    Object row,
    CorrectionSuggestion correction, {
    required DateTime now,
  }) async {
    final assigned = row as _Assigned;
    final subjectId = correction.subjectId;
    final valueId = subjectId.substring(subjectId.indexOf('/') + 1);
    // El valor de antes tiene que seguir en el vocabulario, y el elemento no
    // tenerlo ya puesto por otro lado.
    final value = await (db.select(
      db.propertyValues,
    )..where((v) => v.id.equals(valueId))).getSingleOrNull();
    if (value == null ||
        await _assignment(db, assigned.row.itemId, valueId) != null) {
      return false;
    }
    await _replace(db, assigned.row, withValueId: valueId);
    return true;
  }

  @override
  Future<bool> restoreRemoved(
    AppDatabase db,
    Map<String, dynamic> removed, {
    required DateTime now,
  }) async {
    final row = ItemPropertyValueRow.fromJson(
      removed[_propertyKey] as Map<String, dynamic>,
    );
    final value = await (db.select(
      db.propertyValues,
    )..where((v) => v.id.equals(row.propertyValueId))).getSingleOrNull();
    final item = await (db.select(
      db.knowledgeEntries,
    )..where((e) => e.id.equals(row.itemId))).getSingleOrNull();
    // Que la persona no la haya vuelto a poner ya lo miró quien llama: la
    // asignación es el par elemento y valor, lo mismo que se busca para ver
    // si sigue sacada.
    if (value == null || item == null) return false;
    await db.into(db.itemPropertyValues).insert(row);
    return true;
  }

  @override
  String? removedRunOf(Map<String, dynamic> removed) =>
      (removed[_propertyKey] as Map<String, dynamic>?)?['aiRunId'] as String?;

  Future<ItemPropertyValueRow?> _assignment(
    AppDatabase db,
    String itemId,
    String valueId,
  ) =>
      (db.select(db.itemPropertyValues)..where(
            (p) => p.itemId.equals(itemId) & p.propertyValueId.equals(valueId),
          ))
          .getSingleOrNull();

  Future<void> _delete(AppDatabase db, ItemPropertyValueRow row) =>
      (db.delete(db.itemPropertyValues)..where(
            (p) =>
                p.itemId.equals(row.itemId) &
                p.propertyValueId.equals(row.propertyValueId),
          ))
          .go();

  /// Cambia el valor de la asignación [row] por [withValueId]: la misma de la
  /// IA, de la misma pasada.
  Future<void> _replace(
    AppDatabase db,
    ItemPropertyValueRow row, {
    required String withValueId,
  }) async {
    await _delete(db, row);
    await db
        .into(db.itemPropertyValues)
        .insert(row.copyWith(propertyValueId: withValueId));
  }

  /// Recuerda que [assigned] «no era» en su elemento; `null` si ya estaba.
  Future<String?> _rememberAssignment(
    AppDatabase db,
    _Assigned assigned, {
    required IdGenerator ids,
    required DateTime now,
  }) async {
    final fingerprint = propertyRejectionFingerprint(
      definitionName: assigned.definitionName,
      value: assigned.value,
    );
    if (await isAiRejected(
      db,
      kind: AiRejectionKind.property,
      itemId: assigned.row.itemId,
      fingerprint: fingerprint,
    )) {
      return null;
    }
    return rememberAiRejection(
      db,
      ids: ids,
      now: now,
      kind: AiRejectionKind.property,
      itemId: assigned.row.itemId,
      fingerprint: fingerprint,
      subjectId: assigned.row.propertyValueId,
    );
  }
}

/// El tema que la IA le puso a un elemento, como está hoy: lo que recuerda
/// su pasada y el tema que tiene el elemento.
class _PlacedSpace {
  const _PlacedSpace({
    required this.change,
    required this.itemId,
    required this.runUndone,
    required this.spaceId,
  });

  final AiFieldChangeRow change;
  final String itemId;
  final bool runUndone;

  /// El tema de hoy; `null` si no tiene.
  final String? spaceId;
}

/// El tema de la biblioteca que puso la IA (`AiFieldChanges` con
/// `AiChangedField.space`): se corrige por otro que exista, o se saca.
///
/// Corregirlo actualiza también lo que la pasada recuerda haber puesto
/// (`after_value`): así sigue siendo de la IA, y deshacer esa pasada devuelve
/// el elemento sin tema, como estaba antes de ella. Sacarlo lo deja sin tema y
/// no toca ese registro: la pasada ya no tiene nada en pie.
class _SpaceTarget extends _Target {
  const _SpaceTarget();

  @override
  String get missing => 'Ese elemento ya no está.';

  @override
  String get adopted =>
      'El tema ya es tuyo —lo cambiaste—: la revisión no lo toca.';

  @override
  String get changed =>
      'El tema cambió desde que se revisó: esta corrección ya no vale.';

  @override
  Future<Map<String, Object>> rowsById(AppDatabase db, Set<String> ids) async {
    if (ids.isEmpty) return const {};
    final query =
        db.select(db.aiFieldChanges).join([
          innerJoin(
            db.aiRuns,
            db.aiRuns.id.equalsExp(db.aiFieldChanges.aiRunId),
          ),
          innerJoin(
            db.knowledgeEntries,
            db.knowledgeEntries.id.equalsExp(db.aiRuns.itemId),
          ),
        ])..where(
          db.aiFieldChanges.id.isIn(ids) &
              db.aiFieldChanges.field.equalsValue(AiChangedField.space),
        );
    return {
      for (final joined in await query.get())
        joined.readTable(db.aiFieldChanges).id: _PlacedSpace(
          change: joined.readTable(db.aiFieldChanges),
          itemId: joined.readTable(db.knowledgeEntries).id,
          runUndone: joined.readTable(db.aiRuns).undoneAt != null,
          spaceId: joined.readTable(db.knowledgeEntries).spaceId,
        ),
    };
  }

  @override
  bool isAi(Object row) {
    final placed = row as _PlacedSpace;
    return !placed.runUndone && placed.spaceId == placed.change.afterValue;
  }

  @override
  bool isRemoved(Object? current) =>
      current is _PlacedSpace && current.spaceId == null;

  @override
  bool matches(Object row, Map<String, String> fields) =>
      ((row as _PlacedSpace).spaceId ?? '') == fields[SpaceCorrectionField.id];

  @override
  Future<Either<Failure, Map<String, Object>>> apply(
    AppDatabase db,
    Object row,
    CorrectionSuggestion correction, {
    required IdGenerator ids,
    required DateTime now,
  }) async {
    final placed = row as _PlacedSpace;
    final writer = KnowledgeEntryWriter(db, clock: () => now, ids: ids);
    final after = correction.after;
    if (after != null) {
      final spaceId = after[SpaceCorrectionField.id] ?? '';
      final space = await (db.select(
        db.spaces,
      )..where((s) => s.id.equals(spaceId))).getSingleOrNull();
      if (space == null) {
        return left(
          const Failure.validation(
            message: 'Ese tema ya no está en tu biblioteca.',
          ),
        );
      }
      if (space.id == placed.spaceId) {
        return left(
          const Failure.validation(message: 'La corrección no cambia nada.'),
        );
      }
      await writer.setSpace([placed.itemId], space.id);
      await _rememberPlaced(db, placed.change, space.id);
      return right({
        _afterKey: {
          SpaceCorrectionField.id: space.id,
          SpaceCorrectionField.name: space.name,
        },
      });
    }

    await writer.setSpace([placed.itemId], null);
    return right({
      _removedKey: {
        _itemIdKey: placed.itemId,
        _spaceIdKey: placed.spaceId!,
        _aiRunIdKey: placed.change.aiRunId,
      },
    });
  }

  @override
  Future<bool> restoreBefore(
    AppDatabase db,
    Object row,
    CorrectionSuggestion correction, {
    required DateTime now,
  }) async {
    final placed = row as _PlacedSpace;
    final spaceId = correction.before[SpaceCorrectionField.id]!;
    final space = await (db.select(
      db.spaces,
    )..where((s) => s.id.equals(spaceId))).getSingleOrNull();
    if (space == null) return false;
    await KnowledgeEntryWriter(
      db,
      clock: () => now,
    ).setSpace([placed.itemId], spaceId);
    await _rememberPlaced(db, placed.change, spaceId);
    return true;
  }

  @override
  Future<bool> restoreRemoved(
    AppDatabase db,
    Map<String, dynamic> removed, {
    required DateTime now,
  }) async {
    final spaceId = removed[_spaceIdKey] as String;
    final space = await (db.select(
      db.spaces,
    )..where((s) => s.id.equals(spaceId))).getSingleOrNull();
    if (space == null) return false;
    await KnowledgeEntryWriter(
      db,
      clock: () => now,
    ).setSpace([removed[_itemIdKey] as String], spaceId);
    return true;
  }

  @override
  String? removedRunOf(Map<String, dynamic> removed) =>
      removed[_aiRunIdKey] as String?;

  /// Lo que la pasada de [change] recuerda haber puesto pasa a ser [spaceId].
  Future<void> _rememberPlaced(
    AppDatabase db,
    AiFieldChangeRow change,
    String spaceId,
  ) => (db.update(db.aiFieldChanges)..where((c) => c.id.equals(change.id)))
      .write(AiFieldChangesCompanion(afterValue: Value(spaceId)));
}

/// Un dato de texto de la referencia que completó la IA, como está hoy: lo
/// que recuerda su pasada y la referencia del elemento.
class _FilledReference {
  const _FilledReference({
    required this.change,
    required this.itemId,
    required this.runUndone,
    required this.reference,
  });

  final AiFieldChangeRow change;
  final String itemId;
  final bool runUndone;
  final ReferenceData reference;

  /// El dato hoy, como lo guarda la pasada; `null` si está vacío.
  String? get value => aiFieldValue(change.field, reference, null);
}

/// Un dato de texto de la referencia que completó la IA (`AiFieldChanges`,
/// `AiChangedField.isReferenceText`): se corrige por otro texto, o se vacía.
///
/// Como el tema: corregirlo actualiza también lo que la pasada recuerda
/// haber puesto (`after_value`), así sigue siendo de la IA y deshacer esa
/// pasada lo vacía, como estaba antes de ella. Vaciarlo no toca ese registro.
class _ReferenceTarget extends _Target {
  const _ReferenceTarget();

  @override
  String get missing => 'Ese dato de la referencia ya no está.';

  @override
  String get adopted =>
      'Ese dato ya es tuyo —lo cambiaste—: la revisión no lo toca.';

  @override
  String get changed =>
      'El dato cambió desde que se revisó: esta corrección ya no vale.';

  @override
  Future<Map<String, Object>> rowsById(AppDatabase db, Set<String> ids) async {
    if (ids.isEmpty) return const {};
    final query =
        db.select(db.aiFieldChanges).join([
          innerJoin(
            db.aiRuns,
            db.aiRuns.id.equalsExp(db.aiFieldChanges.aiRunId),
          ),
        ])..where(
          db.aiFieldChanges.id.isIn(ids) &
              db.aiFieldChanges.field.isIn([
                for (final field in AiChangedField.values)
                  if (field.isReferenceText) field.name,
              ]),
        );
    final reader = ReferenceReader(db);
    final found = <String, Object>{};
    for (final joined in await query.get()) {
      final change = joined.readTable(db.aiFieldChanges);
      final run = joined.readTable(db.aiRuns);
      found[change.id] = _FilledReference(
        change: change,
        itemId: run.itemId,
        runUndone: run.undoneAt != null,
        reference: await reader.read(run.itemId),
      );
    }
    return found;
  }

  @override
  bool isAi(Object row) {
    final filled = row as _FilledReference;
    return !filled.runUndone && filled.value == filled.change.afterValue;
  }

  @override
  bool isRemoved(Object? current) =>
      current is _FilledReference && current.value == null;

  @override
  bool matches(Object row, Map<String, String> fields) =>
      ((row as _FilledReference).value ?? '') ==
      fields[ReferenceCorrectionField.value];

  @override
  Future<Either<Failure, Map<String, Object>>> apply(
    AppDatabase db,
    Object row,
    CorrectionSuggestion correction, {
    required IdGenerator ids,
    required DateTime now,
  }) async {
    final filled = row as _FilledReference;
    final field = filled.change.field;
    final writer = KnowledgeEntryWriter(db, clock: () => now, ids: ids);
    final after = correction.after;
    if (after != null) {
      // Lo que va a quedar de verdad —el escritor recorta los textos y
      // normaliza los identificadores—, mirado antes de escribir: una
      // corrección que no se puede aplicar no deja nada a medias.
      final wanted = normalizeReference(
        referenceWithText(
          filled.reference,
          field,
          after[ReferenceCorrectionField.value] ?? '',
        ),
      );
      final stored = aiFieldValue(field, wanted, null);
      if (stored == null) {
        return left(
          const Failure.validation(
            message:
                'Ese valor no sirve para este dato: queda vacío o no es '
                'válido.',
          ),
        );
      }
      if (stored == filled.value) {
        return left(
          const Failure.validation(message: 'La corrección no cambia nada.'),
        );
      }
      await writer.setReference(filled.itemId, wanted);
      await _rememberFilled(db, filled.change, stored);
      return right({
        _afterKey: {
          ...correction.before,
          ReferenceCorrectionField.value: stored,
        },
      });
    }

    await writer.setReference(
      filled.itemId,
      referenceWithText(filled.reference, field, null),
    );
    return right({
      _removedKey: {
        _itemIdKey: filled.itemId,
        _fieldKey: field.name,
        _valueKey: filled.value!,
        _aiRunIdKey: filled.change.aiRunId,
      },
    });
  }

  @override
  Future<bool> restoreBefore(
    AppDatabase db,
    Object row,
    CorrectionSuggestion correction, {
    required DateTime now,
  }) async {
    final filled = row as _FilledReference;
    final before = correction.before[ReferenceCorrectionField.value]!;
    final restored = await KnowledgeEntryWriter(db, clock: () => now)
        .setReference(
          filled.itemId,
          referenceWithText(filled.reference, filled.change.field, before),
        );
    if (!restored) return false;
    await _rememberFilled(db, filled.change, before);
    return true;
  }

  @override
  Future<bool> restoreRemoved(
    AppDatabase db,
    Map<String, dynamic> removed, {
    required DateTime now,
  }) async {
    final itemId = removed[_itemIdKey] as String;
    final field = AiChangedField.values.byName(removed[_fieldKey] as String);
    return KnowledgeEntryWriter(db, clock: () => now).setReference(
      itemId,
      referenceWithText(
        await ReferenceReader(db).read(itemId),
        field,
        removed[_valueKey] as String,
      ),
    );
  }

  @override
  String? removedRunOf(Map<String, dynamic> removed) =>
      removed[_aiRunIdKey] as String?;

  /// Lo que la pasada de [change] recuerda haber puesto pasa a ser [value].
  Future<void> _rememberFilled(
    AppDatabase db,
    AiFieldChangeRow change,
    String value,
  ) => (db.update(db.aiFieldChanges)..where((c) => c.id.equals(change.id)))
      .write(AiFieldChangesCompanion(afterValue: Value(value)));
}

/// Una nota mapa que escribió la IA, como está hoy: si sigue siendo suya, y
/// sus bloques.
class _MapNoteBlocks {
  const _MapNoteBlocks({
    required this.itemId,
    required this.keptByAi,
    required this.renditionId,
    required this.blocks,
  });

  final String itemId;

  /// Viva, generada por la IA, sin editar, y sin que la persona haya
  /// deshecho la pasada que la organizó: lo mismo que mira el Atlas para
  /// mantenerla (`TopicMapNote.keptByAi`).
  final bool keptByAi;
  final String renditionId;
  final List<ContentBlock> blocks;

  /// La introducción: el párrafo que va antes del primer título
  /// (`mapNoteBlocks`); `null` si el modelo no escribió ninguna.
  String? get intro => switch (blocks) {
    [ParagraphBlock(:final text), HeadingBlock(), ...] => text,
    _ => null,
  };

  /// Los bloques con la introducción en [text].
  List<ContentBlock> withIntro(String text) => [
    ContentBlock.paragraph(text: text),
    ...blocks.skip(1),
  ];
}

/// La introducción de una nota mapa de la IA: se corrige su texto, que sigue
/// siendo de la IA —el Atlas la sigue manteniendo—. No se saca: es parte del
/// índice.
class _MapIntroTarget extends _Target {
  const _MapIntroTarget();

  static final _spaces = RegExp(r'\s+');

  @override
  String get missing => 'Esa nota mapa ya no está.';

  @override
  String get adopted =>
      'Esa nota mapa ya es tuya —la editaste—: la revisión no la toca.';

  @override
  String get changed =>
      'La introducción cambió desde que se revisó: esta corrección ya no '
      'vale.';

  @override
  Future<Map<String, Object>> rowsById(AppDatabase db, Set<String> ids) async {
    final found = <String, Object>{};
    for (final id in ids) {
      final row = await db
          .customSelect(
            '''
            SELECT i.deleted_at, n.generated_by_model, n.derived_edited,
                   (SELECT r.undone_at FROM ai_runs r
                     WHERE r.item_id = i.id AND ${organizeRunSql('r')}
                     ORDER BY r.started_at DESC, r.id DESC
                     LIMIT 1) AS last_undone,
                   rd.id AS rendition_id, rd.content
              FROM item i
              JOIN note n ON n.item_id = i.id
              JOIN renditions rd ON rd.item_id = i.id
             WHERE i.id = ? AND n.note_kind = ? AND rd.kind = ?
             ORDER BY rd.is_primary DESC
             LIMIT 1''',
            variables: [
              Variable.withString(id),
              Variable.withString(NoteKind.map.name),
              Variable.withString(RenditionKind.blocks.name),
            ],
            readsFrom: {
              db.knowledgeEntries,
              db.knowledgeNotes,
              db.aiRuns,
              db.renditions,
            },
          )
          .getSingleOrNull();
      if (row == null) continue;
      final blocks = tryDecodeContentBlocks(
        row.readNullable<String>('content') ?? '',
      );
      if (blocks == null) continue;
      found[id] = _MapNoteBlocks(
        itemId: id,
        keptByAi:
            row.readNullable<DateTime>('deleted_at') == null &&
            row.readNullable<String>('generated_by_model') != null &&
            !row.read<bool>('derived_edited') &&
            row.readNullable<DateTime>('last_undone') == null,
        renditionId: row.read<String>('rendition_id'),
        blocks: blocks,
      );
    }
    return found;
  }

  @override
  bool isAi(Object row) => (row as _MapNoteBlocks).keptByAi;

  @override
  bool matches(Object row, Map<String, String> fields) {
    final intro = (row as _MapNoteBlocks).intro;
    return intro != null && intro == fields[MapIntroCorrectionField.text];
  }

  @override
  Future<Either<Failure, Map<String, Object>>> apply(
    AppDatabase db,
    Object row,
    CorrectionSuggestion correction, {
    required IdGenerator ids,
    required DateTime now,
  }) async {
    final note = row as _MapNoteBlocks;
    final after = correction.after;
    if (after == null) {
      return left(
        const Failure.validation(
          message:
              'La introducción de una nota mapa no se saca: es parte del '
              'índice del tema.',
        ),
      );
    }
    // Un solo párrafo, como la escribe la IA (`cleanMapIntro`). Los enlaces
    // de una nota mapa los arma la app con lo que hay en la bóveda: uno que
    // propusiera el modelo podría no llevar a ningún lado.
    final wanted = (after[MapIntroCorrectionField.text] ?? '')
        .replaceAll(_spaces, ' ')
        .trim();
    if (wanted.isEmpty || wanted.contains('[[') || wanted.contains(']]')) {
      return left(
        const Failure.validation(
          message:
              'La introducción corregida tiene que ser un párrafo, sin '
              'enlaces.',
        ),
      );
    }
    if (wanted == note.intro) {
      return left(
        const Failure.validation(message: 'La corrección no cambia nada.'),
      );
    }
    await _write(db, note, wanted, now: now);
    return right({
      _afterKey: {MapIntroCorrectionField.text: wanted},
    });
  }

  @override
  Future<bool> restoreBefore(
    AppDatabase db,
    Object row,
    CorrectionSuggestion correction, {
    required DateTime now,
  }) => _write(
    db,
    row as _MapNoteBlocks,
    correction.before[MapIntroCorrectionField.text]!,
    now: now,
  );

  /// No se saca nada: no hay qué devolver.
  @override
  Future<bool> restoreRemoved(
    AppDatabase db,
    Map<String, dynamic> removed, {
    required DateTime now,
  }) async => false;

  @override
  String? removedRunOf(Map<String, dynamic> removed) => null;

  Future<bool> _write(
    AppDatabase db,
    _MapNoteBlocks note,
    String intro, {
    required DateTime now,
  }) => KnowledgeEntryWriter(db, clock: () => now).setRenditionContent(
    note.itemId,
    note.renditionId,
    encodeContentBlocks(note.withIntro(intro)),
  );
}
