import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/chat/domain/services/chat_passages.dart'
    show foldForSearch;
import 'package:sinapsis/features/chat/presentation/widgets/chat_markdown_blocks.dart';
import 'package:sinapsis/features/help/presentation/help_document.dart';
import 'package:sinapsis/features/help/presentation/providers/help_providers.dart';

/// La guía y las novedades leídas de su Markdown (F47, paso 7): los
/// capítulos, el índice y la búsqueda.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sample = '''
# Guía de prueba

Una presentación que se lee
antes del índice.

## Índice

1. [Primero](#primero)
2. [Segundo capítulo](#segundo-capítulo)

---

## Primero

Un párrafo con **la Bóveda**
partida en dos renglones.

### Una sección

- Un renglón de lista
  que sigue abajo.

#### Algo más adentro

| Columna | Otra |
|---|---|
| celda con bóveda | nada |

## Segundo capítulo

### Otra sección

```
código con bóveda
```
''';

  group('los capítulos', () {
    final document = HelpDocument.parse(sample);

    test('el título de primer nivel es el del documento', () {
      expect(document.title, 'Guía de prueba');
    });

    test('lo de antes del primer capítulo es la presentación', () {
      expect(document.preface, hasLength(1));
      expect(document.preface.single.kind, ChatBlockKind.paragraph);
    });

    test('cada «##» es un capítulo, en orden, con su título como se lee', () {
      expect(document.chapters.map((c) => c.title), [
        'Primero',
        'Segundo capítulo',
      ]);
      expect(document.chapters.map((c) => c.index), [0, 1]);
    });

    test('el índice escrito a mano no es un capítulo: la app arma el suyo', () {
      expect(document.chapters.map((c) => c.title), isNot(contains('Índice')));
    });

    test('un capítulo que tiene algo más que enlaces no es un índice', () {
      final withText = HelpDocument.parse('''
## Índice

Lo que hay acá:

- [Uno](#uno)
''');
      expect(withText.chapters.single.title, 'Índice');
    });

    test('un capítulo con solo su título, o con un separador, no es un '
        'índice', () {
      final bare = HelpDocument.parse('''
## Solo el título

## Con un separador

---
''');
      expect(bare.chapters.map((c) => c.title), [
        'Solo el título',
        'Con un separador',
      ]);
    });

    test('cada «###» es una sección de su capítulo; los de más abajo, no', () {
      expect(document.chapters[0].sections.map((s) => s.title), [
        'Una sección',
      ]);
      expect(document.chapters[1].sections.map((s) => s.title), [
        'Otra sección',
      ]);
      final first = document.chapters[0];
      final heading = first.blocks[first.sections.single.blockIndex];
      expect(heading.kind, ChatBlockKind.heading);
      expect(heading.level, 3);
    });

    test('un capítulo empieza por su título', () {
      for (final chapter in document.chapters) {
        expect(chapter.blocks.first.kind, ChatBlockKind.heading);
        expect(chapter.blocks.first.level, 2);
      }
    });
  });

  group('la búsqueda', () {
    final document = HelpDocument.parse(sample);

    test('sin mayúsculas ni acentos', () {
      final matches = document.search('BOVEDA');
      // El párrafo, la celda y el código.
      expect(matches, hasLength(3));
      expect(matches.map((m) => m.chapter), [0, 0, 1]);
    });

    test('cada lugar apunta al texto crudo de lo encontrado', () {
      for (final match in document.search('bóveda')) {
        expect(
          foldForSearch(sample.substring(match.start, match.end)),
          'boveda',
        );
      }
    });

    test('una frase partida en dos renglones se encuentra igual', () {
      final matches = document.search('lista que sigue');
      expect(matches, hasLength(1));
      expect(
        sample.substring(matches.single.start, matches.single.end),
        'lista\n  que sigue',
      );
    });

    test('el renglón del resultado marca lo encontrado, en un renglón', () {
      final match = document.search('dos renglones').single;
      expect(match.snippet.match, 'dos renglones');
      expect(match.snippet.before, endsWith('partida en '));
      expect(match.snippet.before, isNot(contains('\n')));
    });

    test('lo que no está no da nada, y con una sola letra no busca', () {
      expect(document.search('inexistente'), isEmpty);
      expect(document.search('b'), isEmpty);
      expect(document.search('   '), isEmpty);
    });

    test('dice en qué bloque de su capítulo está', () {
      final match = document.search('celda con').single;
      final block = document.chapters[match.chapter].blocks[match.block];
      expect(block.kind, ChatBlockKind.table);
    });

    test('el índice escrito a mano no da resultados', () {
      expect(document.search('Primero').map((m) => m.chapter), everyElement(0));
    });
  });

  group('la guía de verdad (GUIA_DE_USO.md)', () {
    final raw = File(kUserGuideAsset).readAsStringSync();
    final guide = HelpDocument.parse(raw);
    final lines = raw.split(RegExp(r'\r?\n'));

    String plain(String heading) =>
        displayTextOf(heading, (start: 0, end: heading.length));

    test('censo: cada título de primer nivel de la guía está en el índice, '
        'en orden, salvo su índice escrito a mano', () {
      final topLevel = [
        for (final line in lines)
          if (line.startsWith('## ')) plain(line.substring(3)),
      ];
      expect(topLevel, isNotEmpty);
      final handwritten = topLevel
          .where((title) => !guide.chapters.any((c) => c.title == title))
          .toList();
      // Solo el «Índice» de la guía, que es una lista de enlaces.
      expect(handwritten, ['Índice']);
      expect(guide.chapters.map((c) => c.title).toList(), [
        for (final title in topLevel)
          if (title != 'Índice') title,
      ]);
    });

    test('censo: cada sección («###») está debajo de su capítulo', () {
      final sections = [
        for (final line in lines)
          if (line.startsWith('### ')) plain(line.substring(4)),
      ];
      expect(
        guide.chapters.expand((c) => c.sections).map((s) => s.title),
        sections,
      );
    });

    test('el título y la presentación son los de la guía', () {
      expect(guide.title, 'Guía de uso de Sinapsis');
      expect(guide.preface, isNotEmpty);
    });

    test('la búsqueda encuentra en toda la guía, cruzando capítulos', () {
      final matches = guide.search('bóveda');
      expect(matches.length, greaterThan(20));
      expect(matches.map((m) => m.chapter).toSet().length, greaterThan(3));
      for (final match in matches) {
        expect(foldForSearch(raw.substring(match.start, match.end)), 'boveda');
      }
    });
  });

  group('empaquetada con la app', () {
    test('la guía es la de la raíz, tal cual', () async {
      expect(
        await rootBundle.loadString(kUserGuideAsset, cache: false),
        File(kUserGuideAsset).readAsStringSync(),
      );
    });
  });
}
