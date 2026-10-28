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
    int textOnly = 0,
    int summarized = 0,
    int cut = 0,
    int annotated = 0,
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
    textOnlyCount: textOnly,
    summarizedCount: summarized,
    cutCount: cut,
    annotatedCount: annotated,
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
    expect(markdown, contains('_Generado el 2026-09-21 · 2 ramas_'));
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
          textOnly: 3,
          summarized: 1,
          cut: 1,
          firstYear: -43,
          lastYear: 476,
        ),
      ]),
    );

    expect(
      markdown,
      contains('- **Roma** — Con fragmentos · 5 documentos · 44 a.C. – 476'),
    );
  });

  test('un solo año se dice una vez', () {
    final markdown = lines(
      atlas([
        node('a', 'Año', 0, textOnly: 1, firstYear: 1492, lastYear: 1492),
      ]),
    );

    expect(
      markdown,
      contains('- **Año** — Solo el texto · 1 documento · 1492'),
    );
  });

  test('las notas mapa van como [[enlaces]], sin los caracteres que un enlace '
      'no admite', () {
    final markdown = lines(
      atlas([
        node(
          'roma',
          'Roma',
          0,
          summarized: 2,
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
        node('roma', 'Roma', 0, textOnly: 6),
        node(
          'vieja',
          'Vieja',
          0,
          textOnly: 2,
          lastTouched: DateTime(2025, 9, 2),
        ),
        node('sola', 'Sola', 0, summarized: 1),
      ],
      gaps: const [
        AtlasGap(kind: AtlasGapKind.manyWithoutNotes, valueId: 'roma'),
        AtlasGap(kind: AtlasGapKind.stale, valueId: 'vieja'),
        AtlasGap(kind: AtlasGapKind.singleItem, valueId: 'sola'),
      ],
    );

    final markdown = lines(snapshot);

    expect(markdown, contains('## 3 vacíos detectados'));
    expect(
      markdown,
      contains('- **Roma** — 6 documentos y ninguno con notas propias'),
    );
    expect(markdown, contains('- **Vieja** — Sin tocar hace 12 meses'));
    expect(
      markdown,
      contains('- **Sola** — Un solo documento en toda la rama'),
    );
    // Los vacíos, antes que el árbol.
    expect(
      markdown.indexOf('## 3 vacíos detectados'),
      lessThan(markdown.indexOf('## Ramas')),
    );
  });

  test('sin vacíos, no hay sección de vacíos', () {
    final markdown = atlasToMarkdown(
      atlas([node('roma', 'Roma', 0)]),
      es,
      now: now,
    );

    expect(markdown, isNot(contains('vacío')));
    expect(markdown, contains('## Ramas'));
  });

  test('un Atlas sin ramas es solo el encabezado', () {
    final markdown = atlasToMarkdown(atlas(const []), es, now: now);

    expect(markdown, isNot(contains('## Ramas')));
    expect(markdown, contains('_Generado el 2026-09-21 · 0 ramas_'));
  });

  test('un nombre con caracteres de Markdown no rompe la lista', () {
    final markdown = lines(
      atlas([node('a', 'C* y [1] _raro_ #1', 0, textOnly: 1)]),
    );

    expect(
      markdown,
      contains(r'- **C\* y \[1\] \_raro\_ \#1** — Solo el texto · 1 documento'),
    );
  });

  test('sale en el idioma de la app', () {
    final markdown = atlasToMarkdown(
      atlas([node('roma', 'Roma', 0, textOnly: 3, annotated: 1)]),
      AppLocalizationsEn(),
      now: now,
    );

    expect(markdown, startsWith('# Atlas — Tema\n'));
    expect(markdown, contains('_Generated on 2026-09-21 · 1 branch_'));
    expect(markdown, contains('## Branches'));
    expect(
      markdown,
      contains('- **Roma** — With your own notes · 4 documents · 1 with notes'),
    );
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
