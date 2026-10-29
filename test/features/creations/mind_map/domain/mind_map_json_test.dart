import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/mind_map/domain/mind_map.dart';
import 'package:sinapsis/features/creations/mind_map/domain/mind_map_json.dart';

/// F43, paso 9: el mapa mental se lee con tolerancia —lo que devuelve la IA
/// casi nunca tiene la forma exacta— y se guarda en una forma canónica.
void main() {
  const sources = {'p-exodo': 'Éxodo — Comentario', 'p-genesis': 'Génesis'};

  List<String> labels(MindMapNode node) => [
    for (final child in node.children) child.label,
  ];

  group('la forma canónica', () {
    test('título, raíz, ramas con nota, fuente y pasaje, ids por camino', () {
      final map = MindMapJson.read({
        'title': 'El Éxodo',
        'root': {
          'label': 'Salida de Egipto',
          'children': [
            {
              'label': 'Las plagas',
              'note': 'Diez señales contra el Faraón.',
              'source': 'Éxodo — Comentario',
              'quote': 'el Señor envió diez plagas',
              'children': [
                {'label': 'El Nilo en sangre'},
              ],
            },
            {'label': 'El mar se abre'},
          ],
        },
      }, sources: sources);

      expect(map.title, 'El Éxodo');
      expect(map.root.id, '0');
      expect(map.root.label, 'Salida de Egipto');
      expect(labels(map.root), ['Las plagas', 'El mar se abre']);
      final plagues = map.root.children.first;
      expect(plagues.id, '0.0');
      expect(plagues.note, 'Diez señales contra el Faraón.');
      expect(plagues.source?.documentId, 'p-exodo');
      expect(plagues.source?.documentTitle, 'Éxodo — Comentario');
      expect(plagues.source?.quote, 'el Señor envió diez plagas');
      expect(plagues.children.single.id, '0.0.0');
      expect(map.root.children.last.id, '0.1');
      expect(map.size, 4);
    });

    test('encode y vuelta dan el mismo mapa', () {
      final map = MindMapJson.read({
        'title': 'Mapa',
        'root': {
          'label': 'Raíz',
          'children': [
            {
              'label': 'A',
              'note': 'nota',
              'source': 'Génesis',
              'quote': 'en el principio',
              'children': ['A1', 'A2'],
            },
            'B',
          ],
        },
      }, sources: sources);
      final back = MindMapJson.decode(MindMapJson.encode(map));
      expect(back, map);
      expect(back.root.children.first.source?.documentId, 'p-genesis');
    });
  });

  group('con tolerancia', () {
    test('las claves en castellano, camelCase o snake_case', () {
      final map = MindMapJson.read({
        'Título': 'Mapa',
        'raíz': {
          'nombre': 'Centro',
          'ramas': [
            {
              'texto': 'Uno',
              'descripción': 'la primera',
              'hijos': [
                {'idea': 'Uno.a'},
              ],
            },
            {
              'concepto': 'Dos',
              'sub_temas': [
                {'tema': 'Dos.a'},
              ],
            },
          ],
        },
      });
      expect(map.title, 'Mapa');
      expect(map.root.label, 'Centro');
      expect(labels(map.root), ['Uno', 'Dos']);
      expect(map.root.children.first.note, 'la primera');
      expect(map.root.children.first.children.single.label, 'Uno.a');
      expect(map.root.children.last.children.single.label, 'Dos.a');
    });

    test('la raíz directamente, sin «root»', () {
      final map = MindMapJson.read({
        'label': 'Centro',
        'children': ['Uno', 'Dos'],
      });
      expect(map.root.label, 'Centro');
      expect(map.title, 'Centro');
      expect(labels(map.root), ['Uno', 'Dos']);
    });

    test('una lista de ramas con título: la raíz es el título', () {
      final map = MindMapJson.read({
        'title': 'Éxodo',
        'root': ['Plagas', 'Mar', 'Sinaí'],
      });
      expect(map.root.label, 'Éxodo');
      expect(labels(map.root), ['Plagas', 'Mar', 'Sinaí']);
    });

    test('«{"Idea": [...]}» y objetos de ramas por clave', () {
      final map = MindMapJson.read({
        'root': {
          'label': 'Centro',
          'children': {
            'Plagas': ['Sangre', 'Ranas'],
            'Mar': {
              'note': 'se abre',
              'children': ['Paso'],
            },
            'Sinaí': 'la Ley',
          },
        },
      });
      expect(labels(map.root), ['Plagas', 'Mar', 'Sinaí']);
      expect(labels(map.root.children[0]), ['Sangre', 'Ranas']);
      expect(map.root.children[1].note, 'se abre');
      expect(labels(map.root.children[1]), ['Paso']);
      expect(map.root.children[2].note, 'la Ley');
    });

    test('el texto de la IA, con un bloque de código y una frase antes', () {
      final map = MindMapJson.read(
        '¡Claro! Acá va:\n```json\n{"root": {"label": "Centro", '
        '"children": ["Uno",]}}\n```',
      );
      expect(map.root.label, 'Centro');
      expect(labels(map.root), ['Uno']);
    });

    test('dos hermanas con el mismo nombre se unen, con lo de las dos', () {
      final map = MindMapJson.read({
        'root': {
          'label': 'Centro',
          'children': [
            {
              'label': 'Plagas',
              'children': ['Sangre'],
            },
            {
              'label': ' plágas ',
              'note': 'diez',
              'children': ['Sangre', 'Ranas'],
            },
          ],
        },
      });
      expect(labels(map.root), ['Plagas']);
      expect(map.root.children.single.note, 'diez');
      expect(labels(map.root.children.single), ['Sangre', 'Ranas']);
    });

    test('una idea sin nombre deja sus ramas a la de arriba', () {
      final map = MindMapJson.read({
        'root': {
          'label': 'Centro',
          'children': [
            {
              'children': ['Uno', 'Dos'],
            },
            'Tres',
          ],
        },
      });
      expect(labels(map.root), ['Uno', 'Dos', 'Tres']);
    });

    test('la fuente como número (la primera es la 1) o como objeto', () {
      final map = MindMapJson.read({
        'root': {
          'label': 'Centro',
          'children': [
            {'label': 'A', 'source': 2},
            {
              'label': 'B',
              'source': {'title': 'exodo — comentario', 'quote': 'cita'},
            },
            {'label': 'C', 'fuente': 'Un libro que no está'},
          ],
        },
      }, sources: sources);
      final [a, b, c] = map.root.children;
      expect(a.source?.documentId, 'p-genesis');
      expect(b.source?.documentId, 'p-exodo');
      expect(b.source?.quote, 'cita');
      expect(c.source?.documentId, isNull);
      expect(c.source?.documentTitle, 'Un libro que no está');
    });

    test('un título parecido —contenido en el de la fuente— la reconoce', () {
      final map = MindMapJson.read({
        'root': {
          'label': 'Centro',
          'children': [
            {'label': 'A', 'source': 'Éxodo'},
          ],
        },
      }, sources: sources);
      expect(map.root.children.single.source?.documentId, 'p-exodo');
    });

    test('con una sola fuente, todas las ideas son de ella', () {
      final map = MindMapJson.read(
        {
          'root': {
            'label': 'Centro',
            'children': [
              'A',
              {'label': 'B', 'quote': 'unas palabras'},
            ],
          },
        },
        sources: const {'p-exodo': 'Éxodo'},
      );
      expect(map.root.source?.documentId, 'p-exodo');
      expect(map.root.children.first.source?.documentId, 'p-exodo');
      expect(map.root.children.last.source?.documentId, 'p-exodo');
      expect(map.root.children.last.source?.quote, 'unas palabras');
    });

    test('lo que se pasa de los topes se corta', () {
      final long = 'palabra ' * 40;
      final map = MindMapJson.read({
        'root': {
          'label': long,
          'children': [for (var i = 0; i < 40; i++) 'Rama $i'],
        },
      });
      expect(map.root.label.length, lessThanOrEqualTo(MindMapLimits.label));
      expect(map.root.label, endsWith('…'));
      expect(map.root.children, hasLength(MindMapLimits.children));
    });

    test('más ideas que el tope: quedan los niveles de arriba enteros', () {
      // 20 ramas con 24 hojas cada una: 501 ideas.
      final map = MindMapJson.read({
        'root': {
          'label': 'Centro',
          'children': [
            for (var i = 0; i < 20; i++)
              {
                'label': 'Rama $i',
                'children': [for (var j = 0; j < 24; j++) 'Hoja $i.$j'],
              },
          ],
        },
      });
      expect(map.size, MindMapLimits.nodes);
      // Las veinte ramas están; lo que falta son hojas de las últimas.
      expect(map.root.children, hasLength(20));
      expect(map.root.children.first.children, hasLength(24));
    });

    test('lo que pasa de los niveles se corta', () {
      Object nested(int depth) => depth == 0
          ? 'Hoja'
          : {
              'label': 'Nivel $depth',
              'children': [nested(depth - 1)],
            };
      final map = MindMapJson.read({
        'root': {
          'label': 'Centro',
          'children': [nested(12)],
        },
      });
      expect(map.root.depth, MindMapLimits.depth);
    });
  });

  group('lo que no se puede leer', () {
    test('sin ninguna idea con nombre', () {
      expect(
        () => MindMapJson.read({'foo': 1}),
        throwsA(isA<FormatException>()),
      );
      expect(() => MindMapJson.read(42), throwsA(isA<FormatException>()));
    });

    test('la raíz sin ramas no es un mapa; como borrador de una parte, sí', () {
      expect(
        () => MindMapJson.read({
          'root': {'label': 'Sola'},
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'motivo',
            contains('children'),
          ),
        ),
      );
      final draft = MindMapJson.read({
        'root': {'label': 'Sola'},
      }, partial: true);
      expect(draft.root.label, 'Sola');
    });

    test('varias ramas sin raíz ni título: falta el nombre de la raíz', () {
      expect(
        () => MindMapJson.read(['A', 'B']),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'motivo',
            contains('label'),
          ),
        ),
      );
      // Una sola rama sin raíz: esa es la raíz.
      final single = MindMapJson.read([
        {
          'label': 'A',
          'children': ['A1'],
        },
      ]);
      expect(single.root.label, 'A');
    });

    test('decode de algo roto da un mapa vacío, sin fallar', () {
      final empty = MindMapJson.decode('no es json');
      expect(empty.root.label, isEmpty);
      expect(empty.root.children, isEmpty);
      expect(MindMapJson.tryDecode(null), isNull);
    });
  });

  group('el mapa', () {
    test('pathTo y find', () {
      final map = MindMapJson.read({
        'root': {
          'label': 'R',
          'children': [
            {
              'label': 'A',
              'children': ['A1'],
            },
            'B',
          ],
        },
      });
      expect([for (final n in map.pathTo('0.0.0')) n.label], ['R', 'A', 'A1']);
      expect(map.pathTo('9'), isEmpty);
      expect(map.find('0.1')?.label, 'B');
      expect(map.find('0.7'), isNull);
    });
  });
}
