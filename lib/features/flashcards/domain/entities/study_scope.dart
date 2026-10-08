import 'package:meta/meta.dart';

/// Qué tarjetas se estudian (F31, decisión 69): todas, o un recorte.
///
/// Un recorte es un criterio que se evalúa AL ESTUDIAR, no una lista guardada:
/// una tarjeta nueva de un elemento etiquetado «Roma» entra sola en el recorte
/// «Roma». Es lo que el plan llama «mazo»: no hay mazos que mantener.
@immutable
class StudyScope {
  /// Cualquier tarjeta: sin recorte.
  const StudyScope.all() : kind = StudyScopeKind.all, id = null;

  /// Los elementos de un espacio.
  const StudyScope.space(String this.id) : kind = StudyScopeKind.space;

  /// Un tema o una etiqueta —un valor del vocabulario— CON todas sus ramas:
  /// estudiar «Roma» incluye lo asignado a «Roma republicana».
  const StudyScope.value(String this.id) : kind = StudyScopeKind.value;

  /// Un cuaderno, manual o por consulta, tal como es hoy.
  const StudyScope.notebook(String this.id) : kind = StudyScopeKind.notebook;

  /// Las tarjetas de un solo elemento.
  const StudyScope.item(String this.id) : kind = StudyScopeKind.item;

  final StudyScopeKind kind;

  /// El identificador del espacio, valor, cuaderno o elemento; `null` en
  /// [StudyScopeKind.all].
  final String? id;

  /// Si no restringe nada.
  bool get isAll => kind == StudyScopeKind.all;

  @override
  bool operator ==(Object other) =>
      other is StudyScope && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => 'StudyScope(${kind.name}${id == null ? '' : ': $id'})';
}

/// De qué clase es un [StudyScope].
enum StudyScopeKind { all, space, value, notebook, item }
