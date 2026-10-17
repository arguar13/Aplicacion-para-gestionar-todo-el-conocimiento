import 'package:sinapsis/core/domain/entities/ai_run_scope.dart';

/// Si la pasada [runAlias] de una consulta organizó el elemento (v37,
/// [AiRunScope.organize]): una pasada de solo tarjetas (F30) no cuenta como
/// organizarlo, así que para la cola el elemento sigue pendiente; una
/// revisión (F33), tampoco.
String organizeRunSql(String runAlias) =>
    "$runAlias.scope = '${AiRunScope.organize.name}'";
