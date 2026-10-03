import 'dart:collection';

import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/map/domain/entities/topic_items.dart';

/// Cuántos elementos se reservan, en la vista «Vínculos», para los de los
/// vínculos más recientes: lo que se acaba de vincular se ve en el acto aunque
/// la bóveda tenga cientos de elementos más vinculados (F28).
const kRecentLinkedItems = 40;

/// Un vínculo entre dos elementos vivos, tal como lo entrega la base.
class LinkRow {
  const LinkRow({
    required this.fromId,
    required this.toId,
    required this.kind,
    required this.createdAt,
  });

  final String fromId;
  final String toId;
  final RelationKind kind;
  final DateTime createdAt;
}

/// Qué elementos dibuja la vista «Vínculos» y cuántos vinculados hay en total.
class LinkSelection {
  const LinkSelection({required this.ids, required this.linkedCount});

  /// Los elementos que se dibujan, sin repetir.
  final List<String> ids;

  /// Cuántos elementos tienen algún vínculo entre [LinkRow]s.
  final int linkedCount;
}

/// Elige qué elementos dibuja la vista «Vínculos» (F28) con los vínculos
/// [rows]: todos los que tienen alguno, si no pasan de [limit].
///
/// Si pasan, entran en este orden, hasta llenar el tope:
///
/// 1. **El foco** [focusId] y su vecindario, de a un salto por vez —lo que
///    abre «Ver en el Mapa» desde un vínculo recién creado—.
/// 2. **Lo más reciente**: los extremos de los últimos vínculos, hasta
///    [recent] elementos. Vincular dos cosas se ve en el acto aunque sean
///    dos elementos con un solo vínculo cada uno.
/// 3. **Lo más vinculado**: el resto por cuántos vínculos tiene, que es lo
///    que más dice del dibujo.
///
/// Es puro y no depende del orden en que la base entregó las filas: los
/// empates se desempatan por la fecha del vínculo y por el identificador.
LinkSelection selectLinkGraph(
  List<LinkRow> rows, {
  String? focusId,
  int limit = kMaxGraphItems,
  int recent = kRecentLinkedItems,
}) {
  final degree = HashMap<String, int>();
  final neighbors = HashMap<String, Set<String>>();
  for (final row in rows) {
    if (row.fromId == row.toId) continue;
    degree
      ..update(row.fromId, (d) => d + 1, ifAbsent: () => 1)
      ..update(row.toId, (d) => d + 1, ifAbsent: () => 1);
    (neighbors[row.fromId] ??= {}).add(row.toId);
    (neighbors[row.toId] ??= {}).add(row.fromId);
  }

  int byDegree(String a, String b) {
    final more = degree[b]!.compareTo(degree[a]!);
    return more != 0 ? more : a.compareTo(b);
  }

  final linkedCount = degree.length;
  if (linkedCount <= limit) {
    return LinkSelection(
      ids: degree.keys.toList()..sort(byDegree),
      linkedCount: linkedCount,
    );
  }

  // Un conjunto literal conserva el orden en que entran: el de la selección.
  final chosen = <String>{};
  bool full() => chosen.length >= limit;

  // 1. El foco y su vecindario, por capas: los vecinos directos antes que los
  // de dos saltos, y en cada capa los más vinculados primero.
  if (focusId != null && degree.containsKey(focusId)) {
    var layer = [focusId];
    while (layer.isNotEmpty && !full()) {
      final next = <String>{};
      for (final id in layer) {
        if (full()) break;
        if (!chosen.add(id)) continue;
        next.addAll(neighbors[id]!.where((n) => !chosen.contains(n)));
      }
      layer = next.toList()..sort(byDegree);
    }
  }

  // 2. Los extremos de los vínculos más recientes.
  final newestFirst = [...rows]
    ..sort((a, b) {
      final newer = b.createdAt.compareTo(a.createdAt);
      if (newer != 0) return newer;
      final byFrom = a.fromId.compareTo(b.fromId);
      return byFrom != 0 ? byFrom : a.toId.compareTo(b.toId);
    });
  final recentCap = chosen.length + recent < limit
      ? chosen.length + recent
      : limit;
  for (final row in newestFirst) {
    if (chosen.length >= recentCap) break;
    if (row.fromId == row.toId) continue;
    chosen.add(row.fromId);
    if (chosen.length < recentCap) chosen.add(row.toId);
  }

  // 3. El resto, los más vinculados primero.
  final rest = degree.keys.where((id) => !chosen.contains(id)).toList()
    ..sort(byDegree);
  for (final id in rest) {
    if (full()) break;
    chosen.add(id);
  }

  return LinkSelection(ids: chosen.toList(), linkedCount: linkedCount);
}
