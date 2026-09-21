import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_gap.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_node.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_snapshot.dart';
import 'package:sinapsis/features/atlas/presentation/services/atlas_markdown.dart';
import 'package:sinapsis/l10n/generated/app_localizations_en.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// El Atlas exportado como Markdown (F13): la jerarquía, los conteos, la
/// cobertura, los años, las notas mapa y los vacíos, fuera de la app.
void main() {
  final es = AppLocalizationsEs();
  final now = DateTime(2026, 9, 21, 10);

  AtlasNode node(
    String id,
    String label,
    int depth, {
    String? parent,
    int children = 0,
    int sources = 0,
    int atomic = 0,
    int growing = 0,
    int mature = 0,
    int? firstYear,
    int? lastYear,
    DateTime? lastTouched,
    List<AtlasMapNote> maps = const [],
  }) => AtlasNode(
    valueId: id,
    label: label,
    depth: depth,
    parentId: parent,
    childCount: children,
    sourceCount: sources,
    atomicCount: atomic,
    growingLivingCount: growing,
    matureLivingCount: mature,
    firstYear: firstYear,
    lastYear: lastYear,
    lastTouched: lastTouched,
    mapNotes: maps,
  );

  AtlasSnapshot atlas(
    List<AtlasNode> nodes, {
    List<AtlasGap> gaps = const [],
    String name = 'Tema',
  }) => AtlasSnapshot(
    definitionId: 'tema',
    definitionName: name,
    nodes: nodes,
    gaps: gaps,
  );

  List<String> lines(AtlasSnapshot snapshot) =>
      atlasToMarkdown(snapshot, es, now: now).split('\n');

  test('encabezado: el título con la categoría y la fecha de generación', () {
    final markdown = atlasToMarkdown(
      atlas([node('roma', 'Roma', 0), node('grecia', 'Grecia', 0)]),
      es,
      now: now,
    );

    expect(markdown, startsWith('# Atlas — Tema\n'));
    expect(markdown, contains('_Generado el 2026-09-21 · 2 temas_'));
  });

  test('el árbol es una lista anidada: dos espacios por nivel', () {
    final markdown = lines(
      atlas([
        node('roma', 'Roma', 0, children: 1),
        node('republica', 'República', 1, parent: 'roma', children: 1),
        node('gracos', 'Gracos', 2, parent: 'republica'),
        node('grecia', 'Grecia', 0),
      ]),
    );

    expect(markdown, contains('- **Roma** — Sin material'));
    expect(markdown, contains('  - **República** — Sin material'));
    expect(markdown, contains('    - **Gracos** — Sin material'));
    expect(markdown, contains('- **Grecia** — Sin material'));
  });

  test('cada rama dice su cobertura, sus conteos y los años que cubre', () {
    final markdown = lines(
      atlas([
        node(
          'roma',
          'Roma',
          0,
          sources: 3,
          atomic: 1,
          growing: 1,
          firstYear: -43,
          lastYear: 476,
        ),
      ]),
    );

    expect(
      markdown,
      contains(
        '- **Roma** — En construcción · 3 fuentes · 2 notas · 44 a.C. – 476',
      ),
    );
  });

  test('un solo año se dice una vez', () {
    final markdown = lines(
      atlas([node('a', 'Año', 0, sources: 1, firstYear: 1492, lastYear: 1492)]),
    );

    expect(markdown, contains('- **Año** — Solo fuentes · 1 fuente · 1492'));
  });

  test('las notas mapa van como [[enlaces]], sin los caracteres que un enlace '
      'no admite', () {
    final markdown = lines(
      atlas([
        node(
          'roma',
          'Roma',
          0,
          atomic: 2,
          maps: const [
            AtlasMapNote(id: 'm1', title: 'Mapa de Roma'),
            AtlasMapNote(id: 'm2', title: 'Roma [1] | #ideas ^x'),
          ],
        ),
      ]),
    );

    expect(
      markdown.firstWhere((l) => l.startsWith('- **Roma**')),
      endsWith('Notas mapa: [[Mapa de Roma]], [[Roma 1 ideas x]]'),
    );
  });

  test('los vacíos van primero, con lo que les pasa', () {
    final snapshot = atlas(
      [
        node('roma', 'Roma', 0, sources: 6),
        node(
          'vieja',
          'Vieja',
          0,
          sources: 2,
          lastTouched: DateTime(2025, 9, 2),
        ),
        node('sola', 'Sola', 0, atomic: 1),
      ],
      gaps: const [
        AtlasGap(kind: AtlasGapKind.manySourcesNoLivingNote, valueId: 'roma'),
        AtlasGap(kind: AtlasGapKind.stale, valueId: 'vieja'),
        AtlasGap(kind: AtlasGapKind.singleItem, valueId: 'sola'),
      ],
    );

    final markdown = lines(snapshot);

    expect(markdown, contains('## 3 vacíos detectados'));
    expect(markdown, contains('- **Roma** — 6 fuentes y ninguna nota viva'));
    expect(markdown, contains('- **Vieja** — Sin tocar hace 12 meses'));
    expect(markdown, contains('- **Sola** — Un solo elemento en toda la rama'));
    // Los vacíos, antes que el árbol.
    expect(
      markdown.indexOf('## 3 vacíos detectados'),
      lessThan(markdown.indexOf('## Temas')),
    );
  });

  test('sin vacíos, no hay sección de vacíos', () {
    final markdown = atlasToMarkdown(
      atlas([node('roma', 'Roma', 0)]),
      es,
      now: now,
    );

    expect(markdown, isNot(contains('vacío')));
    expect(markdown, contains('## Temas'));
  });

  test('un Atlas sin temas es solo el encabezado', () {
    final markdown = atlasToMarkdown(atlas(const []), es, now: now);

    expect(markdown, isNot(contains('## Temas')));
    expect(markdown, contains('_Generado el 2026-09-21 · 0 temas_'));
  });

  test('un nombre con caracteres de Markdown no rompe la lista', () {
    final markdown = lines(
      atlas([node('a', 'C* y [1] _raro_ #1', 0, sources: 1)]),
    );

    expect(
      markdown,
      contains(r'- **C\* y \[1\] \_raro\_ \#1** — Solo fuentes · 1 fuente'),
    );
  });

  test('sale en el idioma de la app', () {
    final markdown = atlasToMarkdown(
      atlas([node('roma', 'Roma', 0, sources: 3, mature: 1)]),
      AppLocalizationsEn(),
      now: now,
    );

    expect(markdown, startsWith('# Atlas — Tema\n'));
    expect(markdown, contains('_Generated on 2026-09-21 · 1 topic_'));
    expect(markdown, contains('## Topics'));
    expect(markdown, contains('- **Roma** — Mature · 3 sources · 1 note'));
  });

  test('termina con un salto de línea y no deja líneas en blanco de más', () {
    final markdown = atlasToMarkdown(
      atlas([node('roma', 'Roma', 0)]),
      es,
      now: now,
    );

    expect(markdown, endsWith('\n'));
    expect(markdown, isNot(contains('\n\n\n')));
  });
}
