import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/export/domain/entities/marked_document_format.dart';
import 'package:sinapsis/features/export/domain/entities/marked_document_options.dart';
import 'package:sinapsis/features/export/domain/services/document_marks_builder.dart';
import 'package:sinapsis/features/export/domain/usecases/download_marked_document_usecase.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';

import '../../../../support/fake_file_saver.dart';
import '../../../../support/fake_marked_document_writer.dart';
import '../../../../support/in_memory_file_store.dart';
import '../../../../support/sample_files.dart';
import '../../../../support/sample_knowledge_item.dart';

void main() {
  const content = 'Las fábricas usaban vapor. Nada más.';
  const sentence = 'Las fábricas usaban vapor.';

  const colors = DocumentMarkColors(
    summary: 0xFF000001,
    synthesis: 0xFF000002,
    keyword: 0xFF000003,
    highlights: {},
    defaultHighlight: 0xFF00000B,
  );

  const study = DocumentStudy(
    marks: [
      StudyMark(
        id: 's1',
        kind: StudyMarkKind.summary,
        origin: ContentOrigin.ai,
        start: 0,
        end: sentence.length,
      ),
    ],
    analyzedUntil: content.length,
    complete: true,
  );

  late InMemoryFileStore files;
  late FakeFileSaver saver;
  late Map<MarkedDocumentFormat, FakeMarkedDocumentWriter> writers;

  setUp(() {
    files = InMemoryFileStore();
    saver = FakeFileSaver();
    writers = {
      for (final format in MarkedDocumentFormat.values)
        format: FakeMarkedDocumentWriter(),
    };
  });

  DownloadMarkedDocumentUseCase build({
    Map<MarkedDocumentFormat, FakeMarkedDocumentWriter>? only,
  }) => DownloadMarkedDocumentUseCase(
    files: files,
    writers: only ?? writers,
    saver: saver,
    colors: colors,
  );

  /// Guarda [bytes] como el original de un elemento titulado [title].
  Future<KnowledgeItem> itemWith(
    Uint8List bytes, {
    required String fileName,
    String title = 'Historia',
    SourceKind kind = SourceKind.document,
  }) async {
    final path = await files.save(
      bytes: bytes,
      suggestedName: fileName,
      id: 'item-1',
    );
    final item = sampleKnowledgeItem(title: title);
    return item.copyWith(
      source: item.source.copyWith(kind: kind, originalFilePath: path),
    );
  }

  Future<Either<MarkedDownloadFailure, MarkedDownloadDone>> download(
    DownloadMarkedDocumentUseCase useCase,
    KnowledgeItem item, {
    MarkedDocumentOptions options = const MarkedDocumentOptions(summary: true),
  }) => useCase(
    DownloadMarkedDocumentParams(
      item: item,
      content: content,
      study: study,
      highlights: const [],
      options: options,
    ),
  );

  Uint8List text(String value) => Uint8List.fromList(utf8.encode(value));

  group('elige el escritor y la extensión por el formato del original', () {
    final cases = <(String, Uint8List, String, MarkedDocumentFormat, String)>[
      ('PDF', buildPdf(), 'a.pdf', MarkedDocumentFormat.pdf, 'pdf'),
      ('Word', buildDocx(), 'a.docx', MarkedDocumentFormat.docx, 'docx'),
      ('EPUB', buildEpub(), 'a.epub', MarkedDocumentFormat.epub, 'epub'),
      (
        'texto suelto',
        text('Las fábricas usaban vapor.'),
        'a.txt',
        MarkedDocumentFormat.plainText,
        'docx',
      ),
      (
        'Markdown',
        text('# Las fábricas'),
        'a.md',
        MarkedDocumentFormat.markdown,
        'md',
      ),
    ];

    for (final (label, bytes, name, format, extension) in cases) {
      test(label, () async {
        final item = await itemWith(bytes, fileName: name);

        final result = await download(build(), item);

        expect(result.isRight(), isTrue);
        expect(saver.savedFileName, 'Historia — resumen.$extension');
        for (final entry in writers.entries) {
          expect(
            entry.value.calls,
            entry.key == format ? 1 : 0,
            reason: '${entry.key}',
          );
        }
        expect(writers[format]!.lastOriginal, bytes);
      });
    }

    test('una página web archivada sale como html', () async {
      final item = await itemWith(
        text('<html><body>Las fábricas usaban vapor.</body></html>'),
        fileName: 'pagina.html',
        kind: SourceKind.webPage,
      );

      await download(build(), item);

      expect(saver.savedFileName, 'Historia — resumen.html');
      expect(writers[MarkedDocumentFormat.webPage]!.calls, 1);
    });
  });

  test('le pasa al escritor el texto extraído y los tramos armados', () async {
    final item = await itemWith(buildPdf(), fileName: 'a.pdf');

    await download(build(), item);

    final writer = writers[MarkedDocumentFormat.pdf]!;
    expect(writer.lastContent, content);
    expect(writer.lastMarks, hasLength(1));
    expect(writer.lastMarks!.single.excerpt, sentence);
    expect(writer.lastMarks!.single.color, colors.summary);
  });

  test('guarda lo que escribió el escritor y cuenta dónde quedó', () async {
    final item = await itemWith(buildPdf(), fileName: 'a.pdf');
    saver = FakeFileSaver(path: '/descargas/Historia.pdf');

    final result = await download(build(), item);

    expect(saver.savedBytes, FakeMarkedDocumentWriter.outputFor(1));
    final done = result.getOrElse((_) => throw StateError('falló'));
    expect(done.path, '/descargas/Historia.pdf');
    expect(done.fileName, 'Historia — resumen.pdf');
  });

  test('cancelar el selector no es un error: la ruta es null', () async {
    final item = await itemWith(buildPdf(), fileName: 'a.pdf');
    saver = FakeFileSaver(path: null);

    final result = await download(build(), item);

    expect(result.isRight(), isTrue);
    final done = result.getOrElse((_) => throw StateError('falló'));
    expect(done.path, isNull);
  });

  group('errores', () {
    Future<MarkedDownloadError> errorOf(
      DownloadMarkedDocumentUseCase useCase,
      KnowledgeItem item, {
      MarkedDocumentOptions options = const MarkedDocumentOptions(
        summary: true,
      ),
    }) async {
      final result = await download(useCase, item, options: options);
      expect(result.isLeft(), isTrue);
      return result.match(
        (failure) => failure.error,
        (_) => throw StateError('no falló'),
      );
    }

    test('sin nada elegido', () async {
      final item = await itemWith(buildPdf(), fileName: 'a.pdf');

      expect(
        await errorOf(build(), item, options: const MarkedDocumentOptions()),
        MarkedDownloadError.nothingSelected,
      );
      expect(saver.savedBytes, isNull);
    });

    test('lo elegido no tiene tramos', () async {
      final item = await itemWith(buildPdf(), fileName: 'a.pdf');

      expect(
        await errorOf(
          build(),
          item,
          options: const MarkedDocumentOptions(synthesis: true),
        ),
        MarkedDownloadError.nothingToMark,
      );
      expect(writers[MarkedDocumentFormat.pdf]!.calls, 0);
    });

    test('un elemento sin archivo original', () async {
      final item = sampleKnowledgeItem();

      expect(await errorOf(build(), item), MarkedDownloadError.originalMissing);
    });

    test('un archivo que ya no está guardado', () async {
      final item = await itemWith(buildPdf(), fileName: 'a.pdf');
      await files.delete(item.source.originalFilePath!);

      expect(await errorOf(build(), item), MarkedDownloadError.originalMissing);
    });

    test('un formato que no se sabe marcar', () async {
      final item = await itemWith(buildPlainZip(), fileName: 'a.zip');

      expect(
        await errorOf(build(), item),
        MarkedDownloadError.unsupportedFormat,
      );
    });

    test('un formato sin escritor registrado', () async {
      final item = await itemWith(buildPdf(), fileName: 'a.pdf');

      expect(
        await errorOf(build(only: {}), item),
        MarkedDownloadError.unsupportedFormat,
      );
    });

    test('el escritor falla', () async {
      final item = await itemWith(buildPdf(), fileName: 'a.pdf');
      writers[MarkedDocumentFormat.pdf]!.error = const FormatException('roto');

      expect(await errorOf(build(), item), MarkedDownloadError.writeFailed);
      expect(saver.savedBytes, isNull);
    });

    test('el selector del sistema se cae', () async {
      final item = await itemWith(buildPdf(), fileName: 'a.pdf');
      saver.error = StateError('sin diálogo');

      expect(await errorOf(build(), item), MarkedDownloadError.saveFailed);
    });
  });

  group('el nombre del archivo', () {
    String name(
      String title, {
      MarkedDocumentOptions options = const MarkedDocumentOptions(
        summary: true,
      ),
      MarkedDocumentFormat format = MarkedDocumentFormat.pdf,
    }) =>
        markedDocumentFileName(title: title, options: options, format: format);

    test('título, raya y lo elegido', () {
      expect(name('Historia'), 'Historia — resumen.pdf');
      expect(
        name(
          'Historia',
          options: const MarkedDocumentOptions(
            summary: true,
            myHighlights: true,
          ),
          format: MarkedDocumentFormat.docx,
        ),
        'Historia — resumen y mis resaltados.docx',
      );
    });

    test('sanea lo que un sistema de archivos rechaza', () {
      expect(
        name('Cap. 1: ¿Qué es/fue?'),
        'Cap. 1_ _Qué es_fue_ — resumen.pdf',
      );
      expect(name('../../secreto'), isNot(contains('/')));
      expect(name('///'), 'archivo — resumen.pdf');
    });

    test('un título que ya trae la extensión del documento no la repite', () {
      expect(name('Historia.pdf'), 'Historia — resumen.pdf');
      expect(name('Apuntes.DOCX'), 'Apuntes — resumen.pdf');
      expect(name('Versión 1.2'), 'Versión 1.2 — resumen.pdf');
    });
  });
}
