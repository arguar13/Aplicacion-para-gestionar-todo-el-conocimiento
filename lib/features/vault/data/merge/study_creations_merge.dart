import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/features/vault/data/merge/incoming_vault.dart';

/// Las columnas de «Lo creado» (F43, v48) que copia la unión por conjuntos
/// (`SetUnionMerge`): una creación es de la persona, sin clave foránea a nada
/// —sus fuentes son ids sueltos—. Viven acá y no con las demás columnas por lo
/// mismo que [StudyCreationsMerge]: `deleted_at` es la papelera de la creación.
const kStudyCreationColumns = [
  'id',
  'kind',
  'title',
  'scope_kind',
  'scope_id',
  'source_ids_json',
  'options_json',
  'content_json',
  'content_version',
  'language_code',
  'status',
  'failure',
  'failure_detail',
  'progress',
  'progress_step',
  'run_now',
  'attempts',
  'model_name',
  'created_at',
  'updated_at',
  'deleted_at',
];

/// «Lo creado» de Estudiar (F43) que las dos bóvedas tienen: la misma creación
/// —el mismo id— que llegó de una unión anterior y siguió cambiando de los dos
/// lados.
///
/// Lo que no está acá entra con la unión por conjuntos (`SetUnionMerge`, con
/// `SetUnionRules.studyCreationsFrom`); esto decide sobre las que ya estaban.
/// Va aparte porque una creación tiene su propia papelera (`deleted_at` de
/// `study_creations`) y la unión por conjuntos no decide nada sobre la
/// papelera de los elementos (ver `read_census_test.dart`).
class StudyCreationsMerge {
  const StudyCreationsMerge(this._db);

  final AppDatabase _db;

  static const _incoming = kIncomingSchema;

  /// Queda la versión tocada más tarde, si en la copia está terminada —lista
  /// o fallida— y acá no se está generando: así viajan un título nuevo, lo que
  /// se volvió a generar y el ir y volver de la papelera. Lo que en la copia
  /// estaba a medias no pisa nada: acá nadie lo pidió. Devuelve cuántas
  /// cambiaron.
  Future<int> adoptNewer() => _db.customUpdate(
    '''
    UPDATE main.study_creations SET
      title = x.title,
      source_ids_json = x.source_ids_json,
      options_json = x.options_json,
      content_json = x.content_json,
      content_version = x.content_version,
      language_code = x.language_code,
      status = x.status,
      failure = x.failure,
      failure_detail = x.failure_detail,
      progress = NULL,
      progress_step = NULL,
      model_name = x.model_name,
      updated_at = x.updated_at,
      deleted_at = x.deleted_at
     FROM $_incoming.study_creations x
    WHERE x.id = study_creations.id
      AND x.updated_at > study_creations.updated_at
      AND x.status IN ('ready', 'failed')
      AND study_creations.status IN ('ready', 'failed')''',
    updates: {_db.studyCreations},
  );
}
