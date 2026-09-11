import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/export/data/exporters/markdown_exporter.dart';
import 'package:sinapsis/features/export/data/exporters/pdf_exporter.dart';
import 'package:sinapsis/features/export/data/exporters/plain_text_exporter.dart';
import 'package:sinapsis/features/export/domain/entities/export_format.dart';
import 'package:sinapsis/features/export/domain/exporters/exporter_registry.dart';
import 'package:sinapsis/features/export/domain/services/file_saver.dart';
import 'package:sinapsis/features/export/domain/usecases/export_item_usecase.dart';

import '../../../../support/fake_file_saver.dart';
import '../../../../support/sample_knowledge_item.dart';

void main() {
  const registry = ExporterRegistry([
    MarkdownExporter(),
    PlainTextExporter(),
    PdfExporter(),
  ]);

  ExportItemUseCase build({FileSaver? saver}) =>
      ExportItemUseCase(registry: registry, saver: saver ?? FakeFileSaver());

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
}
