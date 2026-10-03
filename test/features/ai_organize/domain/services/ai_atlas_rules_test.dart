import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_atlas.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_atlas_rules.dart';
import 'package:sinapsis/features/ai_organize/domain/services/map_note_language.dart';

/// Las reglas del Atlas de la IA (F27), sin base ni modelo.
void main() {
  final born = DateTime(2026);

  AtlasTopicTree treeOf(Map<String, String?> parents) => AtlasTopicTree(
    definitionId: 'tema',
    topics: [
      for (final MapEntry(key: label, value: parent) in parents.entries)
        AtlasTopic(id: label, label: label, parentId: parent, createdAt: born),
    ],
  );

  TopicMaterial entry(
    String title, {
    Set<String> values = const {},
    NoteKind? noteKind,
    int day = 1,
  }) => TopicMaterial(
    itemId: title,
    title: title,
    updatedAt: DateTime(2026, 1, day),
    valueIds: values,
    noteKind: noteKind,
  );

  group('los posibles padres de un tema suelto', () {
    final tree = treeOf({
      'Historia': null,
      'Historia antigua': 'Historia',
      'Roma': 'Historia antigua',
      'Arte': null,
      'Escultura': 'Arte',
      'Ejército': 'Historia antigua',
      'Artesanía': null,
      'Roma imperial': null,
      'Suelto': null,
    });

    test('solo temas del árbol: un tema suelto no es padre de nadie', () {
      final candidates = rankParentCandidates(tree, 'Roma imperial');

      expect(candidates, isNot(contains('Artesanía')));
      expect(candidates, isNot(contains('Suelto')));
      expect(candidates, isNot(contains('Roma imperial')));
    });

    test('primero el que está contenido en su nombre, por palabras enteras; '
        'después los del mismo elemento; después los de arriba', () {
      final candidates = rankParentCandidates(
        tree,
        'Roma imperial',
        coTopicIds: ['Escultura', 'Roma imperial'],
      );

      expect(candidates.first, 'Roma');
      // Escultura y su ancestro, Arte, antes que el resto.
      expect(candidates.sublist(1, 3), unorderedEquals(['Arte', 'Escultura']));
      expect(candidates.sublist(3, 5), ['Historia', 'Historia antigua']);
    });

    test('«Arte» no es padre de «Artesanía»: por palabras enteras', () {
      final culture = treeOf({
        'Cultura': null,
        'Arte': 'Cultura',
        'Pintura': 'Arte',
        'Artesanía': null,
        'Arte gótico': null,
      });

      // Sin contener su nombre, «Arte» va después de lo de más arriba.
      expect(rankParentCandidates(culture, 'Artesanía').first, 'Cultura');
      expect(rankParentCandidates(culture, 'Arte gótico').first, 'Arte');
    });

    test('sin árbol, ninguno: la IA no empieza uno', () {
      final flat = treeOf({'A': null, 'B': null, 'C': null});

      expect(rankParentCandidates(flat, 'A'), isEmpty);
    });

    test('nunca más que el tope, ni un padre sin lugar debajo', () {
      final deep = treeOf({
        'N0': null,
        'N1': 'N0',
        'N2': 'N1',
        'N3': 'N2',
        'N4': 'N3',
        'Suelto': null,
      });

      expect(rankParentCandidates(deep, 'Suelto'), isNot(contains('N4')));
      expect(rankParentCandidates(deep, 'Suelto', max: 2), ['N0', 'N1']);
    });
  });

  group('el índice de una nota mapa', () {
    test('sin subtemas: las notas —las vivas primero— y después las fuentes, '
        'cada grupo por título', () {
      final tree = treeOf({'Roma': null});

      final plan = planMapNote(
        tree: tree,
        topicId: 'Roma',
        language: MapNoteLanguage.es,
        material: [
          entry('Zeta', values: {'Roma'}),
          entry('Atómica', values: {'Roma'}, noteKind: NoteKind.atomic),
          entry('Viva', values: {'Roma'}, noteKind: NoteKind.living),
          entry('Alfa', values: {'Roma'}),
        ],
      );

      expect([for (final s in plan.sections) s.heading], ['Notas', 'Fuentes']);
      expect(
        [for (final e in plan.sections[0].entries) e.title],
        ['Viva', 'Atómica'],
      );
      expect(
        [for (final e in plan.sections[1].entries) e.title],
        ['Alfa', 'Zeta'],
      );
      expect(plan.omitted, 0);
    });

    test('con subtemas: una sección por subtema con lo de su rama, y lo del '
        'tema mismo en «General», al final; nada se repite', () {
      final tree = treeOf({
        'Roma': null,
        'República': 'Roma',
        'Imperio': 'Roma',
        'Augusto': 'Imperio',
      });

      final plan = planMapNote(
        tree: tree,
        topicId: 'Roma',
        language: MapNoteLanguage.es,
        material: [
          entry('Octavio', values: {'Augusto'}),
          entry('Senado', values: {'República', 'Imperio'}),
          entry('Cónsules', values: {'República'}),
          entry('Panorama', values: {'Roma'}),
        ],
      );

      expect(
        [for (final s in plan.sections) s.heading],
        ['Imperio', 'República', 'General'],
      );
      expect(
        [for (final e in plan.sections[0].entries) e.title],
        ['Octavio', 'Senado'],
      );
      expect([for (final e in plan.sections[1].entries) e.title], ['Cónsules']);
      expect([for (final e in plan.sections[2].entries) e.title], ['Panorama']);
    });

    test('con más que el tope, entran las notas y lo más reciente, y dice '
        'cuántos quedaron afuera', () {
      final tree = treeOf({'Roma': null});
      final material = [
        for (var day = 1; day <= 6; day++)
          entry('F$day', values: {'Roma'}, day: day),
        entry('Vieja nota', values: {'Roma'}, noteKind: NoteKind.living),
      ];

      final plan = planMapNote(
        tree: tree,
        topicId: 'Roma',
        language: MapNoteLanguage.es,
        material: material,
        maxLinks: 3,
      );

      expect(
        [for (final e in plan.entries) e.title],
        ['Vieja nota', 'F5', 'F6'],
      );
      expect(plan.omitted, 4);
      final blocks = mapNoteBlocks(plan);
      expect(
        blocks.last,
        const ContentBlock.paragraph(text: 'Hay 4 elementos más en este tema.'),
      );
    });

    test('lo que no se puede enlazar, o repite un título, no se lista', () {
      final tree = treeOf({'Roma': null});

      final plan = planMapNote(
        tree: tree,
        topicId: 'Roma',
        language: MapNoteLanguage.es,
        material: [
          entry('Uno', values: {'Roma'}),
          entry('uno ', values: {'Roma'}),
          entry('Con [[corchetes]]', values: {'Roma'}),
          entry('  ', values: {'Roma'}),
        ],
      );

      expect([for (final e in plan.entries) e.title], ['Uno']);
      expect(plan.omitted, 3);
    });

    test('los bloques: la introducción, cada sección con sus enlaces, y se '
        'leen de vuelta como los mismos destinos', () {
      final tree = treeOf({'Roma': null});
      final plan = planMapNote(
        tree: tree,
        topicId: 'Roma',
        language: MapNoteLanguage.es,
        material: [
          entry('Las legiones', values: {'Roma'}),
          entry('Mi nota', values: {'Roma'}, noteKind: NoteKind.living),
        ],
      );

      final blocks = mapNoteBlocks(plan, intro: 'Todo sobre Roma.');

      expect(blocks, const [
        ContentBlock.paragraph(text: 'Todo sobre Roma.'),
        ContentBlock.heading(text: 'Notas', level: 2),
        ContentBlock.bulletItem(text: '[[Mi nota]]'),
        ContentBlock.heading(text: 'Fuentes', level: 2),
        ContentBlock.bulletItem(text: '[[Las legiones]]'),
      ]);
      expect(linkedTitlesOf(encodeContentBlocks(blocks)), plan.linkedTitles);
      expect(plan.linkedTitles, {'las legiones', 'mi nota'});
      expect(linkedTitlesOf(null), isEmpty);
      expect(linkedTitlesOf('no es json'), isEmpty);
    });

    test('en inglés, los textos fijos salen en inglés: los títulos de lo que '
        'enlaza no se traducen', () {
      final tree = treeOf({'Roma': null, 'Imperio': 'Roma'});
      final flat = planMapNote(
        tree: tree,
        topicId: 'Imperio',
        material: [
          entry('Las legiones', values: {'Imperio'}),
          entry('Mi nota', values: {'Imperio'}, noteKind: NoteKind.living),
          entry('Otra', values: {'Imperio'}),
        ],
        language: MapNoteLanguage.en,
        maxLinks: 2,
      );
      final nested = planMapNote(
        tree: tree,
        topicId: 'Roma',
        material: [
          entry('Augusto', values: {'Imperio'}),
          entry('Panorama', values: {'Roma'}),
        ],
        language: MapNoteLanguage.en,
      );

      expect(mapNoteBlocks(flat), const [
        ContentBlock.heading(text: 'Notes', level: 2),
        ContentBlock.bulletItem(text: '[[Mi nota]]'),
        ContentBlock.heading(text: 'Sources', level: 2),
        ContentBlock.bulletItem(text: '[[Las legiones]]'),
        ContentBlock.paragraph(text: 'There is 1 more item in this topic.'),
      ]);
      expect(
        [for (final s in nested.sections) s.heading],
        ['Imperio', 'General'],
      );
    });
  });

  group('el idioma de la nota mapa', () {
    test('el de la app; cualquier otro, inglés, como la app', () {
      expect(MapNoteLanguage.of('es'), MapNoteLanguage.es);
      expect(MapNoteLanguage.of('en'), MapNoteLanguage.en);
      expect(MapNoteLanguage.of('fr'), MapNoteLanguage.en);
    });

    test('cada idioma dice todo', () {
      for (final language in MapNoteLanguage.values) {
        expect(language.title('Roma'), contains('Roma'));
        for (final text in [
          language.notesHeading,
          language.sourcesHeading,
          language.generalHeading,
          language.omitted(1),
          language.omitted(4),
        ]) {
          expect(text.trim(), isNotEmpty);
        }
        expect(language.omitted(4), contains('4'));
      }
      expect(MapNoteLanguage.es.title('Roma'), 'Mapa de Roma');
      expect(MapNoteLanguage.en.title('Roma'), 'Map of Roma');
    });
  });

  group('la madurez que se propone', () {
    test('de semilla a en desarrollo, con largo, vínculos y edad a la vez', () {
      NoteMaturity? grown({
        int length = kDevelopingMinChars,
        int links = kDevelopingMinConnections,
        Duration age = kDevelopingMinAge,
      }) => grownMaturity(
        current: NoteMaturity.seed,
        textLength: length,
        connections: links,
        age: age,
      );

      expect(grown(), NoteMaturity.developing);
      expect(grown(length: kDevelopingMinChars - 1), isNull);
      expect(grown(links: kDevelopingMinConnections - 1), isNull);
      expect(grown(age: const Duration(days: 2)), isNull);
    });

    test(
      'de en desarrollo a madura; nunca salta un nivel ni sube una madura',
      () {
        expect(
          grownMaturity(
            current: NoteMaturity.developing,
            textLength: kMatureMinChars,
            connections: kMatureMinConnections,
            age: kMatureMinAge,
          ),
          NoteMaturity.mature,
        );
        expect(
          grownMaturity(
            current: NoteMaturity.seed,
            textLength: 100000,
            connections: 100,
            age: const Duration(days: 999),
          ),
          NoteMaturity.developing,
        );
        expect(
          grownMaturity(
            current: NoteMaturity.mature,
            textLength: 100000,
            connections: 100,
            age: const Duration(days: 999),
          ),
          isNull,
        );
      },
    );
  });
}
