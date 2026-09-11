import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/export/data/exporters/markdown_exporter.dart';
import 'package:sinapsis/features/export/data/exporters/pdf_exporter.dart';
import 'package:sinapsis/features/export/data/exporters/plain_text_exporter.dart';
import 'package:sinapsis/features/export/domain/exporters/exporter_registry.dart';

final exporterRegistryProvider = Provider<ExporterRegistry>((ref) {
  return const ExporterRegistry([
    MarkdownExporter(),
    PlainTextExporter(),
    PdfExporter(),
  ]);
});
