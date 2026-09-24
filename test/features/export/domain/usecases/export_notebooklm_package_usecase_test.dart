import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/citations/domain/entities/bibliography.dart';
import 'package:sinapsis/features/export/domain/entities/export_format.dart';
import 'package:sinapsis/features/export/domain/entities/notebooklm_export_result.dart';
import 'package:sinapsis/features/export/domain/exporters/exporter.dart';
import 'package:sinapsis/features/export/domain/notebooklm/notebooklm_package_builder.dart';
import 'package:sinapsis/features/export/domain/usecases/export_notebooklm_package_usecase.dart';

import '../../../../support/fake_directory_chooser.dart';
import '../../../../support/fake_directory_writer.dart';
import '../../../../support/sample_knowledge_item.dart';

class _FakeExporter implements Exporter {
  const _FakeExporter();

  @override
  ExportFormat get format => ExportFormat.markdown;

  @override
  String suggestedFileName(KnowledgeItem item) => '${item.title}.md';

  @override
  Future<Uint8List> export(
    KnowledgeItem item, {
    Bibliography? bibliography,
  }) async => Uint8List.fromList(utf8.encode(item.title));
}

void main() {
  const builder = NotebookLmPackageBuilder(exporter: _FakeExporter());

  test('sin elementos, ni siquiera abre el selector de carpeta', () async {
    final chooser = FakeDirectoryChooser(path: '/elegida');
    final useCase = ExportNotebookLmPackageUseCase(
      chooser: chooser,
      writer: FakeDirectoryWriter(),
      builder: builder,
    );

    final result = await useCase([]);

    expect(result.isLeft(), isTrue);
    expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    expect(chooser.callCount, 0);
  });

  test('cancelar el selector no escribe nada', () async {
    final writer = FakeDirectoryWriter();
    final useCase = ExportNotebookLmPackageUseCase(
      chooser: FakeDirectoryChooser(path: null),
      writer: writer,
      builder: builder,
    );

    final result = await useCase([sampleKnowledgeItem()]);

    expect(
      result.getRight().toNullable(),
      const NotebookLmExportResult.cancelled(),
    );
    expect(writer.written, isEmpty);
  });

  test('elegida la carpeta, escribe ahí cada archivo del paquete', () async {
    final writer = FakeDirectoryWriter();
    final useCase = ExportNotebookLmPackageUseCase(
      chooser: FakeDirectoryChooser(path: '/una/carpeta'),
      writer: writer,
      builder: builder,
    );

    final result = await useCase([
      sampleKnowledgeItem(title: 'Uno'),
      sampleKnowledgeItem(title: 'Dos'),
    ]);

    final completed = result.getRight().toNullable();
    expect(completed, isA<NotebookLmExportCompleted>());
    final value = completed! as NotebookLmExportCompleted;
    expect(value.directoryPath, '/una/carpeta');
    // Los dos elementos más el índice.
    expect(value.fileCount, 3);
    expect(
      writer.written.keys,
      containsAll(['Uno.md', 'Dos.md', NotebookLmPackageBuilder.indexFileName]),
    );
    expect(writer.lastDirectoryPath, '/una/carpeta');
  });

  test('si la carpeta no acepta la escritura, lo dice como fallo de '
      'exportación', () async {
    final useCase = ExportNotebookLmPackageUseCase(
      chooser: FakeDirectoryChooser(path: '/sin/permiso'),
      writer: FakeDirectoryWriter(error: StateError('permiso denegado')),
      builder: builder,
    );

    final result = await useCase([sampleKnowledgeItem()]);

    expect(result.isLeft(), isTrue);
    expect(result.getLeft().toNullable(), isA<ExportFailedFailure>());
  });
}
