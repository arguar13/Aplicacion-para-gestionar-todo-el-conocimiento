import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/features/atlas/domain/services/atlas_aggregator.dart';
import 'package:sinapsis/features/atlas/domain/services/atlas_builder.dart';

/// La suma por rama del Atlas (F13), sin base de datos: la cascada por la
/// jerarquía, un elemento una vez por rama y los datos que se arrastran.
void main() {
  final day = DateTime(2026, 9, 2);

  /// roma ─ república ─ gracos, roma ─ imperio, grecia sola.
  final values = [
    const AtlasValueRow(id: 'roma', label: 'Roma'),
    const AtlasValueRow(id: 'republica', label: 'República', parentId: 'roma'),
    const AtlasValueRow(id: 'gracos', label: 'Gracos', parentId: 'republica'),
    const AtlasValueRow(id: 'imperio', label: 'Imperio', parentId: 'roma'),
    const AtlasValueRow(id: 'grecia', label: 'Grecia'),
  ];

  AtlasItemFacts source(
    List<String> valueIds, {
    DateTime? updatedAt,
    int? firstYear,
    int? lastYear,
  }) => AtlasItemFacts(
    isSource: true,
    updatedAt: updatedAt ?? day,
    valueIds: valueIds,
    firstYear: firstYear,
    lastYear: lastYear,
  );

  AtlasItemFacts note(
    NoteKind kind,
    List<String> valueIds, {
    NoteMaturity maturity = NoteMaturity.seed,
  }) => AtlasItemFacts(
    isSource: false,
    noteKind: kind,
    maturity: maturity,
    updatedAt: day,
    valueIds: valueIds,
  );

  Map<String, AtlasBranchCounts> aggregate(List<AtlasItemFacts> items) =>
      aggregateBranches(values: values, items: items);

  test('cada rama trae lo suyo y lo de todos sus descendientes', () {
    final counts = aggregate([
      source(['roma']),
      source(['republica']),
      source(['gracos']),
      source(['imperio']),
      source(['grecia']),
    ]);

    expect(counts['roma']!.sources, 4);
    expect(counts['republica']!.sources, 2);
    expect(counts['gracos']!.sources, 1);
    expect(counts['imperio']!.sources, 1);
    expect(counts['grecia']!.sources, 1);
  });

  test('asignar el hijo no asigna el padre: este lo ve por cascada', () {
    final counts = aggregate([
      source(['gracos']),
    ]);

    expect(counts['gracos']!.sources, 1);
    expect(counts['republica']!.sources, 1);
    expect(counts['roma']!.sources, 1);
    expect(counts.containsKey('imperio'), isFalse);
  });

  test('un elemento en varios valores de una rama cuenta una vez en ella', () {
    final counts = aggregate([
      source(['roma', 'republica', 'gracos']),
      source(['republica', 'imperio']),
    ]);

    expect(counts['roma']!.sources, 2);
    expect(counts['republica']!.sources, 2);
    expect(counts['gracos']!.sources, 1);
    expect(counts['imperio']!.sources, 1);
  });

  test('el mismo valor repetido para un elemento no lo cuenta dos veces', () {
    final counts = aggregate([
      source(['gracos', 'gracos']),
    ]);

    expect(counts['gracos']!.sources, 1);
    expect(counts['roma']!.sources, 1);
  });

  test('las ramas sin ningún elemento no tienen entrada', () {
    final counts = aggregate([
      source(['grecia']),
    ]);

    expect(counts.keys, ['grecia']);
  });

  test('separa fuentes y notas por subtipo y madurez', () {
    final counts = aggregate([
      source(['roma']),
      note(NoteKind.atomic, ['gracos']),
      note(NoteKind.living, ['republica']),
      note(NoteKind.living, ['republica'], maturity: NoteMaturity.developing),
      note(NoteKind.living, ['imperio'], maturity: NoteMaturity.mature),
      note(NoteKind.map, ['roma']),
    ]);

    final roma = counts['roma']!;
    expect(roma.sources, 1);
    expect(roma.atomic, 1);
    expect(roma.growingLiving, 2);
    expect(roma.matureLiving, 1);
    expect(roma.maps, 1);
    final republica = counts['republica']!;
    expect(republica.growingLiving, 2);
    expect(republica.matureLiving, 0);
    expect(republica.atomic, 1);
  });

  test('un elemento sin ningún valor de la categoría no cuenta', () {
    final counts = aggregate([
      source(const []),
      source(['grecia']),
    ]);

    expect(counts.keys, ['grecia']);
    expect(counts['grecia']!.sources, 1);
  });

  test('un valor que no es de la categoría se ignora', () {
    final counts = aggregate([
      source(['de-otra-categoria', 'grecia']),
    ]);

    expect(counts.keys, ['grecia']);
  });

  test('un elemento sin datos de subtipo cuenta como elemento y nada más', () {
    // Una nota sin su fila de subtipo: no es fuente ni de ningún subtipo.
    final counts = aggregate([
      AtlasItemFacts(isSource: false, updatedAt: day, valueIds: ['grecia']),
    ]);

    final grecia = counts['grecia']!;
    expect(grecia.sources + grecia.atomic + grecia.maps, 0);
    expect(grecia.growingLiving + grecia.matureLiving, 0);
    expect(grecia.lastTouched, day);
  });

  group('lo que se arrastra hacia arriba', () {
    test('la última vez que se tocó es la más reciente de la rama entera', () {
      final old = DateTime(2025, 1, 2);
      final recent = DateTime(2026, 8, 30);
      final counts = aggregate([
        source(['roma'], updatedAt: old),
        source(['gracos'], updatedAt: recent),
      ]);

      expect(counts['roma']!.lastTouched, recent);
      expect(counts['republica']!.lastTouched, recent);
      expect(counts['gracos']!.lastTouched, recent);
    });

    test('el rango de años cubre a todos los elementos de la rama', () {
      final counts = aggregate([
        source(['roma'], firstYear: -43, lastYear: -43),
        source(['gracos'], firstYear: 476, lastYear: 480),
        source(['imperio']),
      ]);

      expect(counts['roma']!.firstYear, -43);
      expect(counts['roma']!.lastYear, 480);
      expect(counts['republica']!.firstYear, 476);
      expect(counts['republica']!.lastYear, 480);
      expect(counts['imperio']!.firstYear, isNull);
      expect(counts['imperio']!.lastYear, isNull);
    });
  });

  group('jerarquías raras', () {
    test('un padre que no está entre los valores deja al hijo en la raíz', () {
      final counts = aggregateBranches(
        values: [
          const AtlasValueRow(id: 'hijo', label: 'Hijo', parentId: 'fantasma'),
        ],
        items: [
          source(['hijo']),
        ],
      );

      expect(counts['hijo']!.sources, 1);
    });

    test('un ciclo dañado termina igual y cuenta cada rama una vez', () {
      final counts = aggregateBranches(
        values: [
          const AtlasValueRow(id: 'a', label: 'A', parentId: 'b'),
          const AtlasValueRow(id: 'b', label: 'B', parentId: 'a'),
        ],
        items: [
          source(['a']),
        ],
      );

      expect(counts['a']!.sources, 1);
      expect(counts['b']!.sources, 1);
    });

    test('sin valores o sin elementos, sin conteos', () {
      expect(aggregateBranches(values: const [], items: const []), isEmpty);
      expect(aggregate(const []), isEmpty);
    });
  });
}
