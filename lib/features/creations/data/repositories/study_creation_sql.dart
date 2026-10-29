import 'package:drift/drift.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';

/// La condición SQL de las creaciones vivas que «Lo creado» muestra en
/// [scope] (F43), con su alias [alias] de `study_creations`, y sus variables.
///
/// Un solo lugar la arma para la lista (`StudyCreationRepositoryImpl`) y para
/// la cifra del selector (`CreationScopeResolverImpl`): las dos no pueden
/// discrepar. En un documento son las creadas sobre él y las que lo leyeron
/// como fuente —su id dentro de `source_ids_json`, que `json_each` abre sin
/// traer nada a Dart—; en un cuaderno o un tema, las creadas sobre ese recorte;
/// en «Todo», todas.
({String sql, List<Variable<Object>> variables}) creationsInScopeSql(
  CreationScope scope, {
  String alias = 'c',
}) {
  final live = '$alias.deleted_at IS NULL';
  switch (scope) {
    case AllProcessed():
      return (sql: live, variables: const []);
    case ProcessedDocumentScope(:final documentId):
      return (
        sql: creationsOfDocumentSql('?', alias: alias),
        variables: [
          Variable.withString(documentId),
          Variable.withString(documentId),
        ],
      );
    case NotebookScope() || TopicScope() || SpaceScope():
      return (
        sql: '$live AND $alias.scope_kind = ? AND $alias.scope_id = ?',
        variables: [
          Variable.withString(scope.kindKey),
          Variable.withString(scope.id!),
        ],
      );
  }
}

/// La condición SQL de las creaciones vivas de un documento —[document], una
/// columna, una expresión o `?`, que aparece dos veces—: las creadas sobre él y
/// las que lo leyeron como fuente.
String creationsOfDocumentSql(String document, {String alias = 'c'}) =>
    "$alias.deleted_at IS NULL AND (($alias.scope_kind = 'document' "
    'AND $alias.scope_id = $document) OR EXISTS (SELECT 1 FROM '
    'json_each($alias.source_ids_json) s WHERE s.value = $document))';
