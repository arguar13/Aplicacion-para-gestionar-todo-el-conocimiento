import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/features/citations/domain/entities/bibliography.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';
import 'package:sinapsis/features/citations/domain/services/bibliography_builder.dart';
import 'package:sinapsis/features/citations/domain/services/styles/apa7_style.dart';
import 'package:sinapsis/features/citations/domain/services/styles/ieee_style.dart';
import 'package:sinapsis/features/export/data/exporters/bibliography_docx.dart';
import 'package:sinapsis/features/transform/data/documents/docx_parser.dart';
import 'package:xml/xml.dart';
import '../../../../support/document_parsing.dart';

/// La bibliografía como `.docx` (F15): un documento de verdad, con el título de
/// la lista, una entrada por párrafo, sangría francesa y las cursivas del
/// estilo.
void main() {
  const wordNamespace =
      'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

  BibliographySource book(
    String id,
    String family,
    String title, {
    int? year = 2019,
  }) => BibliographySource(
    itemId: id,
    source: CitationSource(
      title: title,
      reference: ReferenceData(
        type: ReferenceType.book,
        contributors: [
          Contributor(
            name: PersonName(family: family, given: 'Ana'),
          ),
        ],
        publisher: 'Editorial',
      ),
      date: year == null
          ? const PublicationDate.unknown()
          : PublicationDate.ofYear(year),
    ),
  );

  final sources = [
    book('b', 'Borges', 'El Aleph', year: 1949),
    book('a', 'Álvarez', 'Cien años'),
    book('c', 'Zapata', 'Sin fecha', year: null),
  ];

  Bibliography apa({List<BibliographySource>? of}) =>
      buildBibliography(of ?? sources, style: const Apa7Style());

  XmlDocument documentOf(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final file = archive.findFile('word/document.xml')!;
    return XmlDocument.parse(utf8.decode(file.content as List<int>));
  }

  List<XmlElement> paragraphs(XmlDocument document) => document.rootElement
      .getElement('body', namespace: wordNamespace)!
      .findElements('p', namespace: wordNamespace)
      .toList();

  String textOf(XmlElement paragraph) => [
    for (final t in paragraph.findAllElements('t', namespace: wordNamespace))
      t.innerText,
  ].join();

  group('el paquete', () {
    test('es un .docx con lo que Word pide para abrirlo', () {
      final archive = ZipDecoder().decodeBytes(buildBibliographyDocx(apa()));

      expect(
        archive.files.map((f) => f.name),
        containsAll([
          '[Content_Types].xml',
          '_rels/.rels',
          'docProps/core.xml',
          'word/document.xml',
        ]),
      );
    });

    test('el título del documento es el de la lista', () {
      final archive = ZipDecoder().decodeBytes(buildBibliographyDocx(apa()));
      final core = utf8.decode(
        archive.findFile('docProps/core.xml')!.content as List<int>,
      );

      expect(core, contains('Referencias'));
      expect(core, contains('Sinapsis'));
    });
  });

  group('el cuerpo', () {
    test('el título de la lista y una entrada por párrafo, en su orden', () {
      final result = paragraphs(documentOf(buildBibliographyDocx(apa())));

      expect(result, hasLength(4));
      expect(textOf(result[0]), 'Referencias');
      expect(
        [for (final p in result.skip(1)) textOf(p)],
        [for (final e in apa().entries) e.citation.toPlainText()],
      );
      expect(textOf(result[1]), 'Álvarez, A. (2019). Cien años. Editorial.');
    });

    test('el título es un encabezado de primer nivel', () {
      final heading = paragraphs(
        documentOf(buildBibliographyDocx(apa())),
      ).first;
      final properties = heading.getElement('pPr', namespace: wordNamespace)!;

      expect(
        properties
            .getElement('pStyle', namespace: wordNamespace)!
            .getAttribute('val', namespace: wordNamespace),
        'Heading1',
      );
      expect(
        properties
            .getElement('outlineLvl', namespace: wordNamespace)!
            .getAttribute('val', namespace: wordNamespace),
        '0',
      );
    });

    test('cada entrada lleva sangría francesa', () {
      final entries = paragraphs(
        documentOf(buildBibliographyDocx(apa())),
      ).skip(1);

      for (final paragraph in entries) {
        final indent = paragraph
            .getElement('pPr', namespace: wordNamespace)!
            .getElement('ind', namespace: wordNamespace)!;

        expect(indent.getAttribute('left', namespace: wordNamespace), '720');
        expect(indent.getAttribute('hanging', namespace: wordNamespace), '720');
      }
    });

    test('las cursivas del estilo quedan en cursiva', () {
      final entry = paragraphs(documentOf(buildBibliographyDocx(apa())))[1];
      final italics = [
        for (final run in entry.findElements('r', namespace: wordNamespace))
          if (run
                  .getElement('rPr', namespace: wordNamespace)
                  ?.getElement('i', namespace: wordNamespace) !=
              null)
            textOf(run),
      ];

      // El título de un libro, y nada más.
      expect(italics, ['Cien años']);
    });

    test('los huecos van como texto, sin formato', () {
      final entry = paragraphs(documentOf(buildBibliographyDocx(apa())))[3];

      expect(textOf(entry), contains('([falta: año])'));
      expect(
        entry
            .findAllElements('i', namespace: wordNamespace)
            .map((i) => i.parent!.parent)
            .whereType<XmlElement>()
            .map(textOf),
        ['Sin fecha'],
      );
    });

    test('IEEE lleva el número de cada entrada como parte del texto', () {
      final ieee = buildBibliography(sources, style: const IeeeStyle());
      final result = paragraphs(documentOf(buildBibliographyDocx(ieee)));

      expect(textOf(result[1]), startsWith('[1] A. Álvarez, '));
      expect(textOf(result[2]), startsWith('[2] A. Borges, '));
    });

    test('una bibliografía vacía es un documento con solo su título', () {
      final result = paragraphs(
        documentOf(buildBibliographyDocx(apa(of: const []))),
      );

      expect(result, hasLength(1));
      expect(textOf(result.single), 'Referencias');
    });

    test('lo que el usuario escribió no rompe el XML', () {
      final tricky = book('t', 'Tom & Jerry <Inc>', 'Un "título" & más <b>');
      final bibliography = apa(of: [tricky]);
      final result = paragraphs(
        documentOf(buildBibliographyDocx(bibliography)),
      );

      expect(
        textOf(result[1]),
        bibliography.entries.single.citation.toPlainText(),
      );
      expect(textOf(result[1]), contains('Tom & Jerry <Inc>'));
    });
  });

  group('un lector de Word', () {
    test('el propio lector de .docx del proyecto la lee de vuelta', () async {
      // La prueba más fuerte de que esto es un `.docx` de verdad es que el
      // `DocxParser`, pensado para documentos de Word, lo pueda leer.
      final parsed = await const DocxParser().parseBytes(
        buildBibliographyDocx(apa()),
      );

      // Un encabezado de primer nivel; la negrita del título la lee el
      // analizador como negrita.
      expect(
        RegExp(
          r'^# \**Referencias\**$',
          multiLine: true,
        ).hasMatch(parsed.markdown),
        isTrue,
        reason: parsed.markdown,
      );
      expect(parsed.markdown, contains('Álvarez, A. (2019).'));
      expect(parsed.markdown, contains('Borges, A. (1949).'));
      expect(parsed.title, 'Referencias');
    });
  });
}
