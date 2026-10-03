import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vocabulary_tree_rows.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/domain/entities/suggestion_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/core/domain/services/vocabulary_tree.dart';
import 'package:sinapsis/core/error/failures.dart';

/// Lo que la IA hace con el Atlas (F27) y queda en la cola de sugerencias:
/// dónde va un tema suelto en el árbol, y subir la madurez de una nota viva.
///
/// Vive en la capa de base porque lo usan tres repositorios —el de las
/// sugerencias, que las acepta; el de las pasadas, que deshace; y el del
/// Atlas de la IA, que las crea— y la forma del `payload_json` tiene que ser
/// una sola: si cada uno la escribiera a su modo, una se desincronizaría.
///
/// Sin esquema nuevo: los dos tipos son valores de `SuggestionKind` en una
/// columna de texto. Lo que no tiene columna propia —el padre elegido, la
/// pasada que lo aplicó— va en el `payload_json`, que es para eso.

const _definitionIdKey = 'definitionId';
const _valueIdKey = 'valueId';
const _valueNameKey = 'valueName';
const _parentIdKey = 'parentId';
const _parentNameKey = 'parentName';

/// La pasada de la IA que aplicó sola la ubicación: con ella se deshace.
/// Ausente en una propuesta para revisar.
const _aiRunIdKey = 'aiRunId';

const _fromKey = 'from';
const _toKey = 'to';

/// El `payload_json` de una sugerencia `topicParent`.
String encodeTopicParentPayload({
  required String definitionId,
  required String valueId,
  required String valueName,
  required String parentId,
  required String parentName,
  String? aiRunId,
}) => jsonEncode({
  _definitionIdKey: definitionId,
  _valueIdKey: valueId,
  _valueNameKey: valueName,
  _parentIdKey: parentId,
  _parentNameKey: parentName,
  _aiRunIdKey: ?aiRunId,
});

/// El `payload_json` de una sugerencia `maturity`.
String encodeMaturityPayload({
  required NoteMaturity from,
  required NoteMaturity to,
}) => jsonEncode({_fromKey: from.name, _toKey: to.name});

/// La sugerencia `topicParent` de [row].
TopicParentSuggestion topicParentSuggestionOf(SuggestionRow row) {
  final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
  return Suggestion.topicParent(
        id: row.id,
        targetItemId: row.targetItemId,
        definitionId: payload[_definitionIdKey] as String,
        valueId: payload[_valueIdKey] as String,
        valueName: payload[_valueNameKey] as String,
        parentId: payload[_parentIdKey] as String,
        parentName: payload[_parentNameKey] as String,
        aiRunId: payload[_aiRunIdKey] as String?,
        confidence: row.confidence,
        status: row.status,
        createdAt: row.createdAt,
      )
      as TopicParentSuggestion;
}

/// La sugerencia `maturity` de [row].
MaturitySuggestion maturitySuggestionOf(SuggestionRow row) {
  final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
  return Suggestion.maturity(
        id: row.id,
        targetItemId: row.targetItemId,
        from: NoteMaturity.values.byName(payload[_fromKey] as String),
        to: NoteMaturity.values.byName(payload[_toKey] as String),
        confidence: row.confidence,
        status: row.status,
        createdAt: row.createdAt,
      )
      as MaturitySuggestion;
}

/// Las sugerencias `topicParent` sobre el tema [valueId], en cualquier estado
/// y de cualquier elemento: si hay alguna, la IA ya decidió algo sobre ese
/// tema —lo aplicó, lo propuso, la persona lo descartó o lo deshizo— y no lo
/// vuelve a tocar sola.
///
/// El tema vive dentro del JSON: se lee con `json_extract`, como hace «Para
/// revisar» con el otro extremo de un vínculo. Son pocas filas —una por tema
/// suelto que la IA miró—, sin índice que valga la pena.
Future<List<TopicParentSuggestion>> topicParentSuggestionsAbout(
  AppDatabase db,
  String valueId,
) async {
  final rows =
      await (db.select(db.suggestions)..where(
            (s) =>
                s.kind.equalsValue(SuggestionKind.topicParent) &
                _payloadField(_valueIdKey).equals(valueId),
          ))
          .get();
  return rows.map(topicParentSuggestionOf).toList();
}

/// Pone el tema [valueId] bajo [parentId] y recalcula los niveles de su rama.
///
/// Solo si el tema sigue en la raíz: uno que ya tiene padre lo ubicó alguien
/// —la persona, en la pantalla de Vocabulario— y la IA no lo mueve, ni
/// siquiera con una propuesta que la persona acepta tarde (se dice por qué).
/// Las mismas reglas que `VocabularyRepository.moveValue`: el padre existe,
/// es de la misma categoría y de una de texto, y no quedan ciclos ni más de
/// cinco niveles.
///
/// No es `moveValue` porque ese anota el movimiento como un hábito de la
/// persona (F17): lo que hace la IA no le suma a la racha de nadie.
///
/// Corre en la transacción de quien llama: lo que falle después deshace
/// también esto.
Future<Either<Failure, Unit>> placeTopicValue(
  AppDatabase db, {
  required String valueId,
  required String parentId,
}) async {
  final value = await (db.select(
    db.propertyValues,
  )..where((v) => v.id.equals(valueId))).getSingleOrNull();
  if (value == null) {
    return left(
      const Failure.unexpected(
        message: 'El tema ya no existe; puede que se haya borrado.',
      ),
    );
  }
  if (value.parentId != null) {
    return left(
      const Failure.validation(
        message: 'Ese tema ya tiene lugar en el árbol: no se mueve.',
      ),
    );
  }
  final parent = await (db.select(
    db.propertyValues,
  )..where((v) => v.id.equals(parentId))).getSingleOrNull();
  if (parent == null) {
    return left(
      const Failure.unexpected(message: 'El tema de destino ya no existe.'),
    );
  }
  if (parent.definitionId != value.definitionId) {
    return left(
      const Failure.validation(
        message: 'Un tema solo puede ir bajo otro de su misma categoría.',
      ),
    );
  }
  final definition = await (db.select(
    db.propertyDefinitions,
  )..where((d) => d.id.equals(value.definitionId))).getSingle();
  if (definition.type != PropertyValueType.text) {
    return left(
      const Failure.validation(
        message: 'Solo las categorías de texto tienen jerarquía.',
      ),
    );
  }

  final rows = await (db.select(
    db.propertyValues,
  )..where((v) => v.definitionId.equals(value.definitionId))).get();
  final tree = VocabularyTree([
    for (final row in rows) (id: row.id, parentId: row.parentId),
  ]);
  switch (tree.problemMoving(valueId, parentId)) {
    case VocabularyMoveProblem.cycle:
      return left(
        const Failure.validation(
          message: 'Un tema no puede ir bajo sí mismo ni bajo sus subtemas.',
        ),
      );
    case VocabularyMoveProblem.tooDeep:
      return left(
        const Failure.validation(
          message: 'Con esa rama, el árbol pasaría de cinco niveles.',
        ),
      );
    case null:
      break;
  }

  await (db.update(db.propertyValues)..where((v) => v.id.equals(valueId)))
      .write(PropertyValuesCompanion(parentId: Value(parentId)));
  await recomputeDepths(db, [valueId]);
  return right(unit);
}

/// Deshace lo que la IA ubicó sola en el árbol durante la pasada [runId]
/// (F27): cada tema que sigue bajo el padre que ella eligió vuelve a la raíz.
/// Devuelve cuántos volvieron.
///
/// Uno que la persona movió después ya es suyo y queda donde está. En los dos
/// casos el registro queda `rejected`: la IA no vuelve a ubicar sola ese
/// tema, como no vuelve a organizar sola un elemento cuya pasada se deshizo.
///
/// Corre en la transacción de quien llama —`AiRunRepositoryImpl.undoRun`—:
/// o se deshace la pasada entera, o nada.
Future<int> undoAiTopicPlacements(AppDatabase db, String runId) async {
  final rows =
      await (db.select(db.suggestions)..where(
            (s) =>
                s.kind.equalsValue(SuggestionKind.topicParent) &
                s.status.equalsValue(SuggestionStatus.accepted) &
                _payloadField(_aiRunIdKey).equals(runId),
          ))
          .get();
  var restored = 0;
  for (final row in rows) {
    if (await _undoPlacement(db, topicParentSuggestionOf(row))) restored++;
  }
  return restored;
}

/// Deshace una sola ubicación que la IA aplicó sola, la de la sugerencia
/// [suggestionId] (F27): «no era». `right(true)` si el tema volvió a la raíz;
/// `right(false)` si la persona ya lo había movido —queda donde ella lo
/// puso—. Falla si la sugerencia no es una ubicación aplicada por la IA.
///
/// Corre en la transacción de quien llama.
Future<Either<Failure, bool>> undoAiTopicPlacement(
  AppDatabase db,
  String suggestionId,
) async {
  final row = await (db.select(
    db.suggestions,
  )..where((s) => s.id.equals(suggestionId))).getSingleOrNull();
  if (row == null || row.kind != SuggestionKind.topicParent) {
    return left(
      const Failure.unexpected(message: 'Esa ubicación de la IA ya no existe.'),
    );
  }
  final suggestion = topicParentSuggestionOf(row);
  if (suggestion.aiRunId == null ||
      suggestion.status != SuggestionStatus.accepted) {
    return left(
      const Failure.validation(
        message: 'Esa ubicación no la aplicó la IA sola: no hay qué deshacer.',
      ),
    );
  }
  return right(await _undoPlacement(db, suggestion));
}

/// Un campo del `payload_json` de una sugerencia, leído en SQL.
Expression<String> _payloadField(String key) =>
    CustomExpression<String>("json_extract(payload_json, '\$.$key')");

Future<bool> _undoPlacement(
  AppDatabase db,
  TopicParentSuggestion placement,
) async {
  final value = await (db.select(
    db.propertyValues,
  )..where((v) => v.id.equals(placement.valueId))).getSingleOrNull();
  final stillThere = value != null && value.parentId == placement.parentId;
  if (stillThere) {
    await (db.update(db.propertyValues)
          ..where((v) => v.id.equals(placement.valueId)))
        .write(const PropertyValuesCompanion(parentId: Value(null)));
    await recomputeDepths(db, [placement.valueId]);
  }
  await (db.update(
    db.suggestions,
  )..where((s) => s.id.equals(placement.id))).write(
    const SuggestionsCompanion(status: Value(SuggestionStatus.rejected)),
  );
  return stillThere;
}
