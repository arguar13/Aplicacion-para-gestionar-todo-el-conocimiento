import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/processed_depth.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_coverage.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_gap.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_node.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_thresholds.dart';
import 'package:sinapsis/features/atlas/domain/services/atlas_builder.dart';

/// El armado del Atlas (F13): orden del árbol, notas mapa por rama y vacíos.
/// Es puro: lo que la base cuenta entra ya contado.
void main() {
  final now = DateTime(2026, 9, 21, 10);

  AtlasValueRow value(String id, String label, {String? parent}) =>
      AtlasValueRow(id: id, label: label, parentId: parent);

  AtlasNode node(
    String id, {
    int textOnly = 0,
    int summarized = 0,
    int cut = 0,
    int annotated = 0,
  }) => AtlasNode(
    valueId: id,
    label: id,
    depth: 0,
    textOnlyCount: textOnly,
    summarizedCount: summarized,
    cutCount: cut,
    annotatedCount: annotated,
  );

  group('el estado de cobertura es lo más trabajado de la rama (F41)', () {
    test('sin nada asignado, sin material', () {
      expect(node('a').coverage, AtlasCoverage.empty);
    });

    test('documentos con su texto y nada más', () {
      expect(node('a', textOnly: 3).coverage, AtlasCoverage.textOnly);
    });

    test('alguno con resumen o síntesis', () {
      expect(
        node('a', textOnly: 3, summarized: 2).coverage,
        AtlasCoverage.summarized,
      );
    });

    test('alguno con fragmentos cortados a mano', () {
      expect(node('a', summarized: 4, cut: 1).coverage, AtlasCoverage.cut);
    });

    test('alguno con notas propias gana sobre lo demás', () {
      expect(
        node('a', textOnly: 9, cut: 2, annotated: 1).coverage,
        AtlasCoverage.annotated,
      );
    });

    test('los niveles se ordenan de menos a más', () {
      expect(AtlasCoverage.values, [
        AtlasCoverage.empty,
        AtlasCoverage.textOnly,
        AtlasCoverage.summarized,
        AtlasCoverage.cut,
        AtlasCoverage.annotated,
      ]);
    });

    test('el total suma los escalones sin repetir', () {
      final n = node('a', textOnly: 2, summarized: 3, cut: 1, annotated: 1);

      expect(n.itemCount, 7);
      expect(n.countOf(ProcessedDepth.summarized), 3);
      expect(n.countOf(ProcessedDepth.annotated), 1);
    });
  });

  group('el árbol', () {
    AtlasValueRow row(String id, String label, [String? parent]) =>
        value(id, label, parent: parent);

    test(
      'sale en preorden, con hermanos por nombre y sin distinguir acentos',
      () {
        final atlas = buildAtlas(
          definitionId: 'tema',
          definitionName: 'Tema',
          values: [
            row('grecia', 'Grecia'),
            row('roma', 'Roma'),
            row('imperio', 'Imperio', 'roma'),
            row('atica', 'Ática', 'grecia'),
            row('republica', 'República', 'roma'),
            row('beocia', 'Beocia', 'grecia'),
          ],
          counts: const {},
          mapNotes: const [],
          now: now,
        );

        expect(
          [for (final n in atlas.nodes) n.valueId],
          ['grecia', 'atica', 'beocia', 'roma', 'imperio', 'republica'],
        );
        expect([for (final n in atlas.nodes) n.depth], [0, 1, 1, 0, 1, 1]);
        expect(atlas.definitionName, 'Tema');
      },
    );

    test('cada rama sabe su padre y cuántos hijos directos tiene', () {
      final atlas = buildAtlas(
        definitionId: 'tema',
        definitionName: 'Tema',
        values: [
          row('roma', 'Roma'),
          row('republica', 'República', 'roma'),
          row('gracos', 'Gracos', 'republica'),
        ],
        counts: const {},
        mapNotes: const [],
        now: now,
      );

      expect(atlas.nodeOf('roma')!.childCount, 1);
      expect(atlas.nodeOf('gracos')!.childCount, 0);
      expect(atlas.nodeOf('gracos')!.parentId, 'republica');
      expect(atlas.nodeOf('gracos')!.depth, 2);
      expect([for (final n in atlas.roots) n.valueId], ['roma']);
      expect(atlas.nodeOf('no-existe'), isNull);
    });

    test('lo que la base contó llega a cada rama, y lo que no, vale cero', () {
      final touched = DateTime(2026, 8, 5);
      final atlas = buildAtlas(
        definitionId: 'tema',
        definitionName: 'Tema',
        values: [row('roma', 'Roma'), row('grecia', 'Grecia')],
        counts: {
          'roma': AtlasBranchCounts(
            textOnly: 3,
            summarized: 2,
            cut: 1,
            annotated: 1,
            lastTouched: touched,
            firstYear: -753,
            lastYear: 476,
          ),
        },
        mapNotes: const [],
        now: now,
      );

      final roma = atlas.nodeOf('roma')!;
      expect(roma.textOnlyCount, 3);
      expect(roma.summarizedCount, 2);
      expect(roma.cutCount, 1);
      expect(roma.annotatedCount, 1);
      expect(roma.lastTouched, touched);
      expect(roma.firstYear, -753);
      expect(roma.lastYear, 476);
      final grecia = atlas.nodeOf('grecia')!;
      expect(grecia.itemCount, 0);
      expect(grecia.lastTouched, isNull);
      expect(grecia.firstYear, isNull);
    });

    test('sin valores, el Atlas está vacío pero conserva la categoría', () {
      final atlas = buildAtlas(
        definitionId: 'tema',
        definitionName: 'Tema',
        values: const [],
        counts: const {},
        mapNotes: const [],
        now: now,
      );

      expect(atlas.nodes, isEmpty);
      expect(atlas.gaps, isEmpty);
      expect(atlas.definitionId, 'tema');
      expect(atlas.definitionName, 'Tema');
    });

    test('un padre que no está entre los valores deja al hijo en la raíz', () {
      final atlas = buildAtlas(
        definitionId: 'tema',
        definitionName: 'Tema',
        values: [row('hijo', 'Hijo', 'fantasma')],
        counts: const {},
        mapNotes: const [],
        now: now,
      );

      expect(atlas.nodeOf('hijo')!.depth, 0);
      expect(atlas.nodeOf('hijo')!.parentId, isNull);
    });
  });

  group('notas mapa', () {
    List<AtlasValueRow> tree() => [
      value('roma', 'Roma'),
      value('republica', 'República', parent: 'roma'),
      value('gracos', 'Gracos', parent: 'republica'),
      value('grecia', 'Grecia'),
    ];

    test('cuelgan de su valor y de todos sus ascendientes', () {
      final atlas = buildAtlas(
        definitionId: 'tema',
        definitionName: 'Tema',
        values: tree(),
        counts: const {},
        mapNotes: const [
          AtlasMapNoteRow(
            noteId: 'm1',
            title: 'Mapa Gracos',
            valueId: 'gracos',
          ),
        ],
        now: now,
      );

      List<String> ids(String valueId) => [
        for (final note in atlas.nodeOf(valueId)!.mapNotes) note.id,
      ];
      expect(ids('gracos'), ['m1']);
      expect(ids('republica'), ['m1']);
      expect(ids('roma'), ['m1']);
      expect(ids('grecia'), isEmpty);
    });

    test(
      'una nota en varios valores de la rama cuenta una vez, por título',
      () {
        final atlas = buildAtlas(
          definitionId: 'tema',
          definitionName: 'Tema',
          values: tree(),
          counts: const {},
          mapNotes: const [
            AtlasMapNoteRow(
              noteId: 'm2',
              title: 'Mapa de Roma',
              valueId: 'roma',
            ),
            AtlasMapNoteRow(
              noteId: 'm1',
              title: 'Álbum de Roma',
              valueId: 'roma',
            ),
            AtlasMapNoteRow(
              noteId: 'm2',
              title: 'Mapa de Roma',
              valueId: 'gracos',
            ),
          ],
          now: now,
        );

        expect(
          [for (final n in atlas.nodeOf('roma')!.mapNotes) n.title],
          ['Álbum de Roma', 'Mapa de Roma'],
        );
      },
    );
  });

  group('vacíos', () {
    List<AtlasValueRow> tree() => [
      value('roma', 'Roma'),
      value('republica', 'República', parent: 'roma'),
      value('gracos', 'Gracos', parent: 'republica'),
      value('grecia', 'Grecia'),
    ];

    List<(AtlasGapKind, String)> gapsOf(
      Map<String, AtlasBranchCounts> counts, {
      List<AtlasValueRow>? values,
    }) {
      final atlas = buildAtlas(
        definitionId: 'tema',
        definitionName: 'Tema',
        values: values ?? tree(),
        counts: counts,
        mapNotes: const [],
        now: now,
      );
      return [for (final gap in atlas.gaps) (gap.kind, gap.valueId)];
    }

    test('muchos documentos y ninguno con notas: desde el umbral', () {
      final below = gapsOf({
        'grecia': AtlasBranchCounts(
          textOnly: kAtlasManyWithoutNotes - 1,
          lastTouched: now,
        ),
      });
      final at = gapsOf({
        'grecia': AtlasBranchCounts(
          textOnly: kAtlasManyWithoutNotes,
          lastTouched: now,
        ),
      });

      expect(
        below.where((g) => g.$1 == AtlasGapKind.manyWithoutNotes),
        isEmpty,
      );
      expect(at, contains((AtlasGapKind.manyWithoutNotes, 'grecia')));
    });

    test('un documento con notas en la rama quita el vacío; con resumen, '
        'no', () {
      final withNotes = gapsOf({
        'grecia': AtlasBranchCounts(
          textOnly: 9,
          annotated: 1,
          lastTouched: now,
        ),
      });
      final summarizedOnly = gapsOf({
        'grecia': AtlasBranchCounts(
          textOnly: 9,
          summarized: 4,
          lastTouched: now,
        ),
      });

      expect(
        withNotes.map((g) => g.$1),
        isNot(contains(AtlasGapKind.manyWithoutNotes)),
      );
      expect(
        summarizedOnly,
        contains((AtlasGapKind.manyWithoutNotes, 'grecia')),
      );
    });

    test(
      'se avisa en la rama más alta y no se repite en sus descendientes',
      () {
        final gaps = gapsOf({
          'roma': AtlasBranchCounts(textOnly: 12, lastTouched: now),
          'republica': AtlasBranchCounts(textOnly: 10, lastTouched: now),
          'gracos': AtlasBranchCounts(textOnly: 8, lastTouched: now),
        });

        expect(gaps.where((g) => g.$1 == AtlasGapKind.manyWithoutNotes), [
          (AtlasGapKind.manyWithoutNotes, 'roma'),
        ]);
      },
    );

    test('un subtema con muchos documentos se avisa aunque su padre tenga '
        'uno con notas', () {
      final gaps = gapsOf({
        'roma': AtlasBranchCounts(textOnly: 12, annotated: 1, lastTouched: now),
        'republica': AtlasBranchCounts(textOnly: 7, lastTouched: now),
        'gracos': AtlasBranchCounts(textOnly: 7, lastTouched: now),
      });

      expect(gaps.where((g) => g.$1 == AtlasGapKind.manyWithoutNotes), [
        (AtlasGapKind.manyWithoutNotes, 'republica'),
      ]);
    });

    test('una rama con un solo elemento, en la más alta que lo cumple', () {
      final gaps = gapsOf({
        'roma': AtlasBranchCounts(summarized: 1, lastTouched: now),
        'republica': AtlasBranchCounts(summarized: 1, lastTouched: now),
        'gracos': AtlasBranchCounts(summarized: 1, lastTouched: now),
        'grecia': AtlasBranchCounts(textOnly: 2, lastTouched: now),
      });

      expect(gaps.where((g) => g.$1 == AtlasGapKind.singleItem), [
        (AtlasGapKind.singleItem, 'roma'),
      ]);
    });

    test('una rama vacía no es un vacío: es el estado «sin material»', () {
      expect(gapsOf(const {}), isEmpty);
    });

    test('sin tocar desde hace el umbral o más: abandonada', () {
      final old = now.subtract(kAtlasStaleAfter);
      final recent = now.subtract(kAtlasStaleAfter - const Duration(days: 1));
      final gaps = gapsOf({
        'grecia': AtlasBranchCounts(textOnly: 2, lastTouched: old),
        'roma': AtlasBranchCounts(textOnly: 2, lastTouched: recent),
      });

      expect(gaps.where((g) => g.$1 == AtlasGapKind.stale), [
        (AtlasGapKind.stale, 'grecia'),
      ]);
    });

    test('la última vez que se tocó es la de toda la rama: un hijo reciente '
        'salva al padre', () {
      final old = now.subtract(const Duration(days: 400));
      // La consulta ya entrega el máximo de la rama entera: el padre trae la
      // fecha del hijo reciente.
      final gaps = gapsOf({
        'roma': AtlasBranchCounts(textOnly: 2, lastTouched: now),
        'republica': AtlasBranchCounts(textOnly: 1, lastTouched: old),
        'gracos': AtlasBranchCounts(textOnly: 1, lastTouched: old),
      });

      expect(
        gaps.where((g) => g.$1 == AtlasGapKind.stale).map((g) => g.$2),
        unorderedEquals(['republica']),
      );
    });

    test('las abandonadas van de la más vieja a la más nueva', () {
      final gaps = gapsOf({
        'grecia': AtlasBranchCounts(
          textOnly: 2,
          lastTouched: now.subtract(const Duration(days: 300)),
        ),
        'roma': AtlasBranchCounts(
          textOnly: 2,
          lastTouched: now.subtract(const Duration(days: 500)),
        ),
      });

      expect(gaps.where((g) => g.$1 == AtlasGapKind.stale).map((g) => g.$2), [
        'roma',
        'grecia',
      ]);
    });

    test('primero las fuentes sin nota viva, después las abandonadas y al '
        'final las de un solo elemento', () {
      final old = now.subtract(const Duration(days: 400));
      final gaps = gapsOf({
        'roma': AtlasBranchCounts(textOnly: 1, lastTouched: now),
        'grecia': AtlasBranchCounts(textOnly: 6, lastTouched: old),
      });

      expect(
        [for (final g in gaps) g.$1],
        [
          AtlasGapKind.manyWithoutNotes,
          AtlasGapKind.stale,
          AtlasGapKind.singleItem,
        ],
      );
    });
  });
}
