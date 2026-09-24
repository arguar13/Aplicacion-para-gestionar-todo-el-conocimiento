import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/features/citations/domain/entities/bibliography.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';
import 'package:sinapsis/features/citations/domain/services/bibliography_builder.dart';
import 'package:sinapsis/features/citations/domain/services/styles/apa7_style.dart';
import 'package:sinapsis/features/export/domain/entities/export_format.dart';
import 'package:sinapsis/features/export/domain/services/bibliography_file_builder.dart';

void main() {
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

  group('bibliographyFormats', () {
    test(
      'no incluye BibTeX: esa exportación es de una obra, no de la lista',
      () {
        expect(bibliographyFormats, isNot(contains(ExportFormat.bibtex)));
      },
    );

    test('sí incluye Markdown, texto plano, PDF y Word', () {
      expect(
        bibliographyFormats,
        containsAll(const [
          ExportFormat.markdown,
          ExportFormat.plainText,
          ExportFormat.pdf,
          ExportFormat.docx,
        ]),
      );
    });
  });

  group('buildBibliographyFile', () {
    test('Markdown lleva el título como encabezado y las cursivas', () async {
      final bytes = await buildBibliographyFile(
        bibliography(),
        ExportFormat.markdown,
      );
      final text = utf8.decode(bytes);

      expect(text, startsWith('# Referencias'));
      expect(text, contains('*Un libro citado*'));
    });

    test('el texto plano no lleva cursivas', () async {
      final bytes = await buildBibliographyFile(
        bibliography(),
        ExportFormat.plainText,
      );
      final text = utf8.decode(bytes);

      expect(text, contains('Un libro citado'));
      expect(text, isNot(contains('*Un libro citado*')));
    });

    test('el PDF empieza con la cabecera de un PDF de verdad', () async {
      final bytes = await buildBibliographyFile(
        bibliography(),
        ExportFormat.pdf,
      );

      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('el .docx es un ZIP de verdad', () async {
      final bytes = await buildBibliographyFile(
        bibliography(),
        ExportFormat.docx,
      );

      expect(bytes.take(2), [0x50, 0x4B]); // "PK", la firma de un ZIP.
    });

    test('un .bib lanza: no es un formato de bibliografía', () async {
      await expectLater(
        () => buildBibliographyFile(bibliography(), ExportFormat.bibtex),
        throwsArgumentError,
      );
    });
  });

  group('suggestedBibliographyFileName', () {
    test('usa el nombre del alcance, no el título de la lista', () {
      expect(
        suggestedBibliographyFileName('Un espacio', ExportFormat.markdown),
        'Un espacio.md',
      );
    });

    test('sanea el nombre igual que un exportador cualquiera', () {
      expect(
        suggestedBibliographyFileName('Con / barra', ExportFormat.pdf),
        isNot(contains('/')),
      );
    });
  });
}
