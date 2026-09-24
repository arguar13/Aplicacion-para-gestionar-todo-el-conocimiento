import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/citations/domain/entities/bibliography.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';
import 'package:sinapsis/features/citations/domain/services/styles/apa7_style.dart';
import 'package:sinapsis/features/export/data/exporters/bibtex_exporter.dart';
import 'package:sinapsis/features/export/data/exporters/markdown_exporter.dart';
import 'package:sinapsis/features/export/data/exporters/pdf_exporter.dart';
import 'package:sinapsis/features/export/data/exporters/plain_text_exporter.dart';
import 'package:sinapsis/features/export/domain/entities/export_format.dart';
import 'package:sinapsis/features/export/domain/exporters/exporter_registry.dart';
import 'package:sinapsis/features/export/domain/services/file_saver.dart';
import 'package:sinapsis/features/export/domain/usecases/export_item_usecase.dart';

import '../../../../support/fake_bibliography_repository.dart';
import '../../../../support/fake_file_saver.dart';
import '../../../../support/sample_knowledge_item.dart';

void main() {
  const registry = ExporterRegistry([
    MarkdownExporter(),
    PlainTextExporter(),
    PdfExporter(),
    BibtexExporter(),
  ]);

  ExportItemUseCase build({
    FileSaver? saver,
    FakeBibliographyRepository? bibliography,
  }) => ExportItemUseCase(
    registry: registry,
    saver: saver ?? FakeFileSaver(),
    bibliography: bibliography ?? FakeBibliographyRepository(),
    citationStyle: const Apa7Style(),
    citationLanguage: CitationLanguage.es,
  );

  test('exporta en el formato pedido y se lo pasa al selector', () async {
    final saver = FakeFileSaver();
    final useCase = build(saver: saver);
    final item = sampleKnowledgeItem(title: 'Un artículo');

    final result = await useCase(
      ExportItemParams(item: item, format: ExportFormat.markdown),
    );

    expect(result.isRight(), isTrue);
    expect(saver.savedFileName, endsWith('.md'));
    expect(saver.savedBytes, isNotNull);
    expect(saver.savedBytes!.isNotEmpty, isTrue);
  });

  test('cada formato produce su propia extensión', () async {
    final saver = FakeFileSaver();
    final useCase = build(saver: saver);
    final item = sampleKnowledgeItem();

    await useCase(ExportItemParams(item: item, format: ExportFormat.pdf));

    expect(saver.savedFileName, endsWith('.pdf'));
  });

  test(
    'si el selector de guardado falla, es un fallo de exportación',
    () async {
      final useCase = build(
        saver: FakeFileSaver(error: StateError('el diálogo se cayó')),
      );

      final result = await useCase(
        ExportItemParams(
          item: sampleKnowledgeItem(),
          format: ExportFormat.markdown,
        ),
      );

      expect(result.isLeft(), isTrue);
      expect(result.getLeft().toNullable(), isA<ExportFailedFailure>());
    },
  );

  group('la bibliografía al pie de una nota (F15, D13)', () {
    KnowledgeItem note({String id = 'nota-1'}) {
      final item = sampleKnowledgeItem(title: 'Una nota').copyWith(id: id);
      return item.copyWith(
        source: item.source.copyWith(kind: SourceKind.manualNote),
      );
    }

    final cited = [
      BibliographySource(
        itemId: 'fuente-1',
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
    ];

    test('con algo citado, la agrega al archivo', () async {
      final saver = FakeFileSaver();
      final useCase = build(
        saver: saver,
        bibliography: FakeBibliographyRepository(citedBy: cited),
      );

      await useCase(
        ExportItemParams(item: note(), format: ExportFormat.markdown),
      );

      final content = utf8.decode(saver.savedBytes!);
      expect(content, contains('García'));
    });

    test('pide la bibliografía de la nota que se exporta', () async {
      final bibliography = FakeBibliographyRepository(citedBy: cited);
      final useCase = build(bibliography: bibliography);

      await useCase(
        ExportItemParams(
          item: note(id: 'nota-7'),
          format: ExportFormat.markdown,
        ),
      );

      expect(bibliography.calls, ['nota-7']);
    });

    test('sin nada citado, no pide guardar nada de más', () async {
      final saver = FakeFileSaver();
      final useCase = build(
        saver: saver,
        bibliography: FakeBibliographyRepository(),
      );

      await useCase(
        ExportItemParams(item: note(), format: ExportFormat.markdown),
      );

      final content = utf8.decode(saver.savedBytes!);
      expect(content, isNot(contains('García')));
    });

    test('una fuente no "cita" nada: no se pide su bibliografía', () async {
      final bibliography = FakeBibliographyRepository(citedBy: cited);
      final useCase = build(bibliography: bibliography);

      await useCase(
        ExportItemParams(
          item: sampleKnowledgeItem(),
          format: ExportFormat.markdown,
        ),
      );

      expect(bibliography.calls, isEmpty);
    });

    test('un .bib no la lleva: ya es una referencia', () async {
      final bibliography = FakeBibliographyRepository(citedBy: cited);
      final useCase = build(bibliography: bibliography);

      await useCase(
        ExportItemParams(item: note(), format: ExportFormat.bibtex),
      );

      expect(bibliography.calls, isEmpty);
    });

    test('un texto plano no la lleva: no tiene con qué separarla', () async {
      final bibliography = FakeBibliographyRepository(citedBy: cited);
      final useCase = build(bibliography: bibliography);

      await useCase(
        ExportItemParams(item: note(), format: ExportFormat.plainText),
      );

      expect(bibliography.calls, isEmpty);
    });
  });
}
