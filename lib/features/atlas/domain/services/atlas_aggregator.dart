import 'dart:typed_data';

import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/features/atlas/domain/services/atlas_builder.dart';

/// Un elemento VIVO tal como el Atlas lo cuenta: qué es, cuándo se tocó por
/// última vez, qué años cubren sus «Fecha del hecho» y qué valores de la
/// categoría tiene puestos.
class AtlasItemFacts {
  const AtlasItemFacts({
    required this.isSource,
    required this.updatedAt,
    required this.valueIds,
    this.noteKind,
    this.maturity,
    this.firstYear,
    this.lastYear,
  });

  /// Una fuente. Si no lo es, es una nota y trae [noteKind] y [maturity].
  final bool isSource;
  final NoteKind? noteKind;
  final NoteMaturity? maturity;
  final DateTime updatedAt;

  /// El año astronómico más temprano y el más tardío de sus fechas del hecho,
  /// o `null` si no tiene ninguna.
  final int? firstYear;
  final int? lastYear;

  /// Los valores de la categoría que tiene asignados, cada uno una vez.
  final List<String> valueIds;
}

/// Lo que se cuenta en cada rama: los cinco conteos de `AtlasBranchCounts`.
const _sources = 0;
const _atomic = 1;
const _growingLiving = 2;
const _matureLiving = 3;
const _maps = 4;
const _kinds = 5;

/// Suma, para CADA rama de la categoría, lo que hay en ella y en todos sus
/// subtemas (F13): el motor de conteos en cascada del Atlas.
///
/// [items] son los elementos vivos —los de la papelera no vienen— con los
/// valores de la categoría que tienen. Uno asignado a varios valores de la
/// misma rama cuenta UNA vez en ella; uno sin ningún valor no cuenta en
/// ninguna, y un valor que no es de [values] se ignora. Las ramas sin ningún
/// elemento no tienen entrada.
///
/// Hace en Dart, en una pasada, lo que en SQL era un `DISTINCT` de (rama,
/// elemento) sobre ~60.000 pares de textos y una consulta por cada uno para
/// traer sus datos —más de la mitad del segundo que tardaba abrir el Atlas con
/// 10.000 elementos—. Acá, por cada elemento se sube desde cada uno de sus
/// valores hasta la raíz marcando lo visitado: al topar con una rama ya marcada
/// para ESE elemento se corta, porque todo lo de arriba también lo está. Es una
/// visita por (elemento, rama) y nada más.
Map<String, AtlasBranchCounts> aggregateBranches({
  required List<AtlasValueRow> values,
  required Iterable<AtlasItemFacts> items,
}) {
  final size = values.length;
  final indexOf = {for (var i = 0; i < size; i++) values[i].id: i};
  // El padre de cada valor por posición; -1 para una raíz. Un padre que no
  // está entre los valores deja al hijo en la raíz.
  final parent = Int32List(size)..fillRange(0, size, -1);
  for (var i = 0; i < size; i++) {
    final parentId = values[i].parentId;
    if (parentId != null) parent[i] = indexOf[parentId] ?? -1;
  }

  final counts = Int32List(size * _kinds);
  final total = Int32List(size);
  final lastTouched = List<DateTime?>.filled(size, null);
  final firstYear = List<int?>.filled(size, null);
  final lastYear = List<int?>.filled(size, null);

  // La última vez que se visitó cada rama, para saber si ya se contó ESTE
  // elemento en ella: una marca por elemento y no un conjunto por elemento.
  final visitedFor = Int32List(size);
  var stamp = 0;

  for (final item in items) {
    if (item.valueIds.isEmpty) continue;
    stamp++;
    final kind = _kindOf(item);
    for (final valueId in item.valueIds) {
      var branch = indexOf[valueId] ?? -1;
      // Una jerarquía dañada con un ciclo termina igual: la marca corta.
      while (branch != -1 && visitedFor[branch] != stamp) {
        visitedFor[branch] = stamp;
        total[branch]++;
        if (kind != -1) counts[branch * _kinds + kind]++;
        final touched = lastTouched[branch];
        if (touched == null || item.updatedAt.isAfter(touched)) {
          lastTouched[branch] = item.updatedAt;
        }
        final from = item.firstYear;
        if (from != null) {
          final first = firstYear[branch];
          if (first == null || from < first) firstYear[branch] = from;
        }
        final to = item.lastYear;
        if (to != null) {
          final last = lastYear[branch];
          if (last == null || to > last) lastYear[branch] = to;
        }
        branch = parent[branch];
      }
    }
  }

  return {
    for (var i = 0; i < size; i++)
      if (total[i] > 0)
        values[i].id: AtlasBranchCounts(
          sources: counts[i * _kinds + _sources],
          atomic: counts[i * _kinds + _atomic],
          growingLiving: counts[i * _kinds + _growingLiving],
          matureLiving: counts[i * _kinds + _matureLiving],
          maps: counts[i * _kinds + _maps],
          lastTouched: lastTouched[i],
          firstYear: firstYear[i],
          lastYear: lastYear[i],
        ),
  };
}

/// En cuál de los cinco conteos entra un elemento; -1 si no entra en ninguno
/// —una nota sin su fila de subtipo—: cuenta como elemento de la rama, y solo
/// eso.
int _kindOf(AtlasItemFacts item) {
  if (item.isSource) return _sources;
  return switch (item.noteKind) {
    NoteKind.atomic => _atomic,
    NoteKind.map => _maps,
    NoteKind.living =>
      item.maturity == NoteMaturity.mature ? _matureLiving : _growingLiving,
    null => -1,
  };
}
