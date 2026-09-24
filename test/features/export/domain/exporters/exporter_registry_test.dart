import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/citations/domain/entities/bibliography.dart';
import 'package:sinapsis/features/export/domain/entities/export_format.dart';
import 'package:sinapsis/features/export/domain/exporters/exporter.dart';
import 'package:sinapsis/features/export/domain/exporters/exporter_registry.dart';

class _FakeExporter implements Exporter {
  const _FakeExporter(this.format);

  @override
  final ExportFormat format;

  @override
  String suggestedFileName(KnowledgeItem item) => 'archivo.${format.name}';

  @override
  Future<Uint8List> export(
    KnowledgeItem item, {
    Bibliography? bibliography,
  }) async => Uint8List(0);
}

void main() {
  group('resolve', () {
    test('devuelve el exportador que declara ese formato', () {
      const markdown = _FakeExporter(ExportFormat.markdown);
      const pdf = _FakeExporter(ExportFormat.pdf);
      const registry = ExporterRegistry([markdown, pdf]);

      expect(registry.resolve(ExportFormat.markdown), same(markdown));
      expect(registry.resolve(ExportFormat.pdf), same(pdf));
    });

    test('lanza si no hay ninguno para ese formato', () {
      const registry = ExporterRegistry([_FakeExporter(ExportFormat.pdf)]);

      expect(
        () => registry.resolve(ExportFormat.markdown),
        throwsA(isA<StateError>()),
      );
    });
  });
}
