import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/ai_rejection_kind.dart';
import 'package:sinapsis/core/util/id_generator.dart';

/// La memoria de lo que «no era» (F27), sobre `ai_rejections`: recordar,
/// olvidar y preguntar. Las huellas las arma `ai_rejection_fingerprint.dart`;
/// acá solo se guardan y se buscan por su clave única.
///
/// La comparten los repositorios que borran algo de la IA —vínculos,
/// tarjetas, propiedades— y el que la consulta antes de aplicar nada, para que
/// los tres digan «lo mismo» exactamente igual.

/// Recuerda que la persona dijo que esto «no era» y devuelve el id de la fila
/// que lo recuerda. Si ya estaba recordado —lo mismo, otra vez—, devuelve el
/// de antes y no escribe nada: se recuerda una sola vez.
Future<String> rememberAiRejection(
  AppDatabase db, {
  required IdGenerator ids,
  required DateTime now,
  required AiRejectionKind kind,
  required String itemId,
  required String fingerprint,
  String? otherItemId,
  String? subjectId,
}) async {
  final existing = await _find(
    db,
    kind: kind,
    itemId: itemId,
    fingerprint: fingerprint,
  );
  if (existing != null) return existing.id;

  final id = ids.next();
  await db
      .into(db.aiRejections)
      .insert(
        AiRejectionsCompanion.insert(
          id: id,
          kind: kind,
          itemId: itemId,
          otherItemId: Value(otherItemId),
          fingerprint: fingerprint,
          subjectId: Value(subjectId),
          createdAt: now,
        ),
      );
  return id;
}

/// Olvida la fila [rejectionId]: deshacer un «no era» vuelve a dejar que la
/// IA lo proponga.
Future<void> forgetAiRejection(AppDatabase db, String rejectionId) =>
    (db.delete(db.aiRejections)..where((r) => r.id.equals(rejectionId))).go();

/// Si la persona dijo que esto «no era».
Future<bool> isAiRejected(
  AppDatabase db, {
  required AiRejectionKind kind,
  required String itemId,
  required String fingerprint,
}) async =>
    await _find(db, kind: kind, itemId: itemId, fingerprint: fingerprint) !=
    null;

Future<AiRejectionRow?> _find(
  AppDatabase db, {
  required AiRejectionKind kind,
  required String itemId,
  required String fingerprint,
}) =>
    (db.select(db.aiRejections)..where(
          (r) =>
              r.kind.equalsValue(kind) &
              r.itemId.equals(itemId) &
              r.fingerprint.equals(fingerprint),
        ))
        .getSingleOrNull();
