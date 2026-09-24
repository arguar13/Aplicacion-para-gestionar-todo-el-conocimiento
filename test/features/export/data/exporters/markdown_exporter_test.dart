import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/entities/tag.dart';
import 'package:sinapsis/features/citations/domain/entities/bibliography.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';
import 'package:sinapsis/features/citations/domain/services/bibliography_builder.dart';
import 'package:sinapsis/features/citations/domain/services/styles/apa7_style.dart';
import 'package:sinapsis/features/export/data/exporters/markdown_exporter.dart';
import 'package:sinapsis/features/export/domain/entities/export_format.dart';

import '../../../../support/sample_knowledge_item.dart';

void main() {
  const exporter = MarkdownExporter();

  Future<String> exportToString(KnowledgeItem item) async =>
      utf8.decode(await exporter.export(item));

  group('formato', () {
    test('es markdown', () {
      expect(exporter.format, ExportFormat.markdown);
    });
  });

  group('nombre de archivo', () {
    test('usa el título saneado con extensión .md', () {
      final item = sampleKnowledgeItem(title: 'Título: con / caracteres?');

      expect(exporter.suggestedFileName(item), endsWith('.md'));
      expect(exporter.suggestedFileName(item), isNot(contains('/')));
      expect(exporter.suggestedFileName(item), isNot(contains(':')));
    });
  });

  group('cabecera YAML', () {
    test('trae el título, el tipo de fuente y la fecha de captura', () async {
      final text = await exportToString(
        sampleKnowledgeItem(
          title: 'Un título cualquiera',
          capturedAt: DateTime(2026, 9, 11, 10, 30),
        ),
      );

      expect(text, startsWith('---\n'));
      expect(text, contains('title: "Un título cualquiera"'));
      expect(text, contains('source_kind: webPage'));
      expect(text, contains('captured_at: "2026-09-11T10:30:00.000"'));
    });

    test('trae el enlace y el autor cuando existen', () async {
      final text = await exportToString(
        sampleKnowledgeItem(
          url: 'https://ejemplo.org/articulo',
          authorName: 'Ada Lovelace',
          authorUrl: 'https://ejemplo.org/ada',
          publishedAt: DateTime(2020),
        ),
      );

      expect(text, contains('url: "https://ejemplo.org/articulo"'));
      expect(text, contains('author: "Ada Lovelace"'));
      expect(text, contains('author_url: "https://ejemplo.org/ada"'));
      expect(text, contains('published_at: "2020-01-01T00:00:00.000"'));
    });

    test('omite lo que no tiene, no inventa campos vacíos', () async {
      final text = await exportToString(
        sampleKnowledgeItem(url: null, authorName: null),
      );

      expect(text, isNot(contains('url:')));
      expect(text, isNot(contains('author:')));
      expect(text, isNot(contains('published_at:')));
    });

    test('las etiquetas salen como lista', () async {
      final text = await exportToString(
        sampleKnowledgeItem(
          tags: [
            Tag(id: 't1', name: 'filosofía', createdAt: DateTime(2026)),
            Tag(id: 't2', name: 'ciencia', createdAt: DateTime(2026)),
          ],
        ),
      );

      expect(text, contains('tags:\n  - "filosofía"\n  - "ciencia"'));
    });

    test('sin etiquetas no escribe la clave', () async {
      final text = await exportToString(sampleKnowledgeItem());

      expect(text, isNot(contains('tags:')));
    });

    test('escapa comillas y barras invertidas en los valores', () async {
      final text = await exportToString(
        sampleKnowledgeItem(title: r'Un "título" con \barra'),
      );

      expect(text, contains(r'title: "Un \"título\" con \\barra"'));
    });
  });

  group('cuerpo', () {
    test('el título va como encabezado de primer nivel', () async {
      final text = await exportToString(
        sampleKnowledgeItem(title: 'Un artículo interesante'),
      );

      expect(text, contains('\n# Un artículo interesante\n'));
    });

    test('el subtítulo va en cursiva, si existe', () async {
      final text = await exportToString(
        sampleKnowledgeItem(subtitle: 'Un subtítulo'),
      );

      expect(text, contains('*Un subtítulo*'));
    });

    test('sin subtítulo no deja una línea en cursiva vacía', () async {
      final text = await exportToString(sampleKnowledgeItem(subtitle: null));

      expect(text, isNot(contains('**')));
    });

    test('las notas van como una cita', () async {
      final text = await exportToString(
        sampleKnowledgeItem(notes: 'Una nota\ncon dos líneas'),
      );

      expect(text, contains('> Una nota\n> con dos líneas'));
    });

    test('sin notas no aparece ninguna cita', () async {
      // El `>` de una cita de Markdown siempre abre línea; no alcanza con
      // buscar el carácter suelto, porque el pie de procedencia lo usa
      // también para el enlace entre `< >`.
      final text = await exportToString(sampleKnowledgeItem());

      expect(text, isNot(contains('\n> ')));
    });

    test('el contenido de las formas de texto llega entero', () async {
      final text = await exportToString(
        sampleKnowledgeItem(
          renditions: [sampleTextRendition('El cuerpo del artículo.')],
        ),
      );

      expect(text, contains('El cuerpo del artículo.'));
    });

    test(
      'sin ninguna forma de texto, lo dice en vez de dejarlo en blanco',
      () async {
        final text = await exportToString(sampleKnowledgeItem());

        expect(text, contains('Sin contenido extraído todavía.'));
      },
    );
  });

  group('pie de procedencia', () {
    test('repite la fecha, la fuente y el autor en texto corriente', () async {
      final text = await exportToString(
        sampleKnowledgeItem(
          capturedAt: DateTime(2026, 9, 11),
          url: 'https://ejemplo.org/a',
          authorName: 'Ada Lovelace',
        ),
      );

      expect(text, contains('Guardado el 2026-09-11.'));
      expect(text, contains('Fuente: <https://ejemplo.org/a>'));
      expect(text, contains('Autor: Ada Lovelace'));
    });

    test(
      'si hay perfil de autor, enlaza el perfil y no solo el nombre',
      () async {
        final text = await exportToString(
          sampleKnowledgeItem(
            authorName: 'Ada Lovelace',
            authorUrl: 'https://ejemplo.org/ada',
          ),
        );

        expect(text, contains('Autor: <https://ejemplo.org/ada>'));
        expect(text, isNot(contains('Autor: Ada Lovelace')));
      },
    );
  });

  group('bibliografía al pie (F15, D13)', () {
    Bibliography bibliography() => buildBibliography([
      BibliographySource(
        itemId: 'f1',
        source: CitationSource(
          title: 'Un libro citado',
          reference: const ReferenceData(
            type: ReferenceType.book,
            contributors: [Contributor(name: PersonName(family: 'García'))],
            publisher: 'Editorial',
          ),
          date: PublicationDate.ofYear(2020),
        ),
      ),
    ], style: const Apa7Style());

    test('va después de la procedencia, con su título', () async {
      final text = utf8.decode(
        await const MarkdownExporter().export(
          sampleKnowledgeItem(),
          bibliography: bibliography(),
        ),
      );

      expect(text, contains('## Referencias'));
      expect(text, contains('García'));
      expect(
        text.indexOf('Guardado el'),
        lessThan(text.indexOf('## Referencias')),
      );
    });

    test('las cursivas del estilo llegan como Markdown', () async {
      final text = utf8.decode(
        await const MarkdownExporter().export(
          sampleKnowledgeItem(),
          bibliography: bibliography(),
        ),
      );

      expect(text, contains('*Un libro citado*'));
    });

    test('sin bibliografía, no agrega la sección', () async {
      final text = await exportToString(sampleKnowledgeItem());

      expect(text, isNot(contains('## Referencias')));
    });

    test('una bibliografía vacía tampoco agrega la sección', () async {
      final text = utf8.decode(
        await const MarkdownExporter().export(
          sampleKnowledgeItem(),
          bibliography: buildBibliography(const [], style: const Apa7Style()),
        ),
      );

      expect(text, isNot(contains('## Referencias')));
    });
  });
}
