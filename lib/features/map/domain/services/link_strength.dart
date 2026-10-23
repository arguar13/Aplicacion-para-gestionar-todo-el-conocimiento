import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/map/domain/services/link_graph_builder.dart';

/// Qué parte de los vínculos dibuja la vista «Vínculos» del Mapa (F39,
/// paso 8): la mitad que más pesa, la mitad que menos pesa o todos.
enum LinkStrengthFilter {
  /// La mitad de mayor peso.
  strongest,

  /// La mitad de menor peso.
  weakest,

  /// Todos: lo de siempre.
  all,
}

/// Cuánto pesa un vínculo, de lo que la base ya guarda de él.
///
/// Suma cuatro cosas, cada una con una razón:
///
/// - **El tipo** (1 a 3): `relatedTo` es «se tocan» y no dice qué (1);
///   `contradicts` es de los más valiosos al estudiar un tema (3, igual que
///   pesa entre temas); los demás dicen algo preciso (2).
/// - **Quién lo respaldó** (0 a 1): lo que la persona hizo, adoptó al editarlo
///   o marcó como revisado vale 1; lo que dejó la IA sola vale su
///   `confidence` a la mitad (0 a 0,5; sin dato, 0): nadie lo confirmó.
/// - **Si sabe de dónde sale** (0,5): un vínculo con el fragmento del texto
///   del destino (lo que guarda una extracción desde una selección) tiene un
///   respaldo que uno suelto no tiene.
/// - **Cuántas veces se vinculan los dos** (+1 por cada vínculo de más): dos
///   elementos unidos por varios vínculos —de otro tipo o en el otro sentido—
///   se citan mutuamente más que dos unidos por uno.
///
/// Va de 1 a 4 más lo que sumen los vínculos repetidos. [pairLinks] es
/// cuántos vínculos hay en total entre sus dos extremos, este incluido (1 si
/// está solo); `cutLinksByStrength` lo cuenta.
///
/// Es pura: no mira la fecha ni el título, nada que cambie por abrir la app.
double linkStrength(LinkRow link, {int pairLinks = 1}) {
  final kind = switch (link.kind) {
    RelationKind.relatedTo => 1.0,
    RelationKind.contradicts => 3.0,
    RelationKind.continues ||
    RelationKind.cites ||
    RelationKind.summarizes ||
    RelationKind.extractedFrom ||
    RelationKind.indexes => 2.0,
  };
  final confirmed =
      link.origin == ContentOrigin.user || link.reviewedAt != null;
  final backing = confirmed
      ? 1.0
      : (link.confidence ?? 0).clamp(0.0, 1.0) * 0.5;
  final anchor = link.anchored ? 0.5 : 0.0;
  final repeated = pairLinks > 1 ? pairLinks - 1 : 0;
  return kind + backing + anchor + repeated;
}

/// Los vínculos de [rows] que muestra [filter].
///
/// Los ordena de más a menos pesado (`linkStrength`, con cuántos hay entre
/// cada par de elementos) y devuelve la mitad —redondeada hacia arriba— de la
/// punta que se pide: `strongest` la de arriba, `weakest` la de abajo.
/// Redondear hacia arriba hace que con un solo vínculo, o con un número
/// impar, ninguna de las dos mitades quede vacía: el del medio está en las
/// dos. `all` devuelve [rows] tal cual.
///
/// Los empates se desempatan siempre igual, sin mirar el orden en que llegaron
/// las filas: el más reciente primero y, si aun así empatan, por los
/// identificadores y el tipo. Un vínculo de un elemento consigo mismo no
/// cuenta (la base no lo permite).
List<LinkRow> cutLinksByStrength(
  List<LinkRow> rows,
  LinkStrengthFilter filter,
) {
  if (filter == LinkStrengthFilter.all) return rows;

  // Cuántos vínculos hay entre cada par, sin importar el sentido.
  String pairOf(LinkRow row) => row.fromId.compareTo(row.toId) < 0
      ? '${row.fromId}\u0000${row.toId}'
      : '${row.toId}\u0000${row.fromId}';
  final perPair = <String, int>{};
  final valid = [
    for (final row in rows)
      if (row.fromId != row.toId) row,
  ];
  for (final row in valid) {
    perPair.update(pairOf(row), (n) => n + 1, ifAbsent: () => 1);
  }

  final strength = {
    for (final row in valid)
      row: linkStrength(row, pairLinks: perPair[pairOf(row)]!),
  };
  final heaviestFirst = [...valid]
    ..sort((a, b) {
      final heavier = strength[b]!.compareTo(strength[a]!);
      if (heavier != 0) return heavier;
      final newer = b.createdAt.compareTo(a.createdAt);
      if (newer != 0) return newer;
      final byFrom = a.fromId.compareTo(b.fromId);
      if (byFrom != 0) return byFrom;
      final byTo = a.toId.compareTo(b.toId);
      return byTo != 0 ? byTo : a.kind.name.compareTo(b.kind.name);
    });

  final half = (heaviestFirst.length + 1) ~/ 2;
  return switch (filter) {
    LinkStrengthFilter.strongest => heaviestFirst.take(half).toList(),
    LinkStrengthFilter.weakest =>
      heaviestFirst.skip(heaviestFirst.length - half).toList(),
    LinkStrengthFilter.all => rows,
  };
}
