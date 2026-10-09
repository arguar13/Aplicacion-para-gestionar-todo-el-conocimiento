import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';

/// A dónde ir para ver las tarjetas de [scope] en «Mis tarjetas» (F31, ola 2,
/// decisión 72): `/cards`, con el recorte en la consulta.
String myCardsLocation([StudyScope scope = const StudyScope.all()]) {
  final id = scope.id;
  if (id == null) return kRouteCards;
  final key = switch (scope.kind) {
    StudyScopeKind.all => null,
    StudyScopeKind.space => 'space',
    StudyScopeKind.value => 'value',
    StudyScopeKind.notebook => 'notebook',
    StudyScopeKind.item => 'item',
  };
  return key == null
      ? kRouteCards
      : '$kRouteCards?$key=${Uri.encodeQueryComponent(id)}';
}

/// El recorte de una ruta de `/cards`: lo inverso de [myCardsLocation]. Sin
/// consulta, o con una que no se entiende, todo.
StudyScope myCardsScopeFromQuery(Map<String, String> query) {
  final item = query['item'];
  if (item != null && item.isNotEmpty) return StudyScope.item(item);
  final notebook = query['notebook'];
  if (notebook != null && notebook.isNotEmpty) {
    return StudyScope.notebook(notebook);
  }
  final value = query['value'];
  if (value != null && value.isNotEmpty) return StudyScope.value(value);
  final space = query['space'];
  if (space != null && space.isNotEmpty) return StudyScope.space(space);
  return const StudyScope.all();
}
