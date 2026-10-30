import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/export/domain/entities/marked_document_format.dart';
import 'package:sinapsis/features/export/domain/entities/marked_document_options.dart';
import 'package:sinapsis/features/export/domain/services/document_marks_builder.dart';
import 'package:sinapsis/features/export/domain/usecases/download_marked_document_usecase.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note_target.dart';

import '../../../../support/fake_file_saver.dart';
import '../../../../support/fake_marked_document_writer.dart';
import '../../../../support/in_memory_file_store.dart';
import '../../../../support/sample_knowledge_item.dart';

/// Las notas en el texto (F45, mejora 19) en lo que se descarga marcado:
/// cuáles van, dónde, con qué color, y que lleguen al escritor.
void main() {
  const content = 'Moisés sube al monte. Baja con las tablas de la ley.';
  const target = TextNoteTarget.sourceOriginal(
    sourceId: 'fuente',
    renditionId: 'rend',
  );

  const colors = DocumentMarkColors(
    summary: 0xFF000001,
    synthesis: 0xFF000002,
    keyword: 0xFF000003,
    highlights: {HighlightColor.violet: 0xFF0000A1},
    defaultHighlight: 0xFF00000B,
    underlines: {HighlightColor.violet: 0xFF0000B1},
    defaultUnderline: 0xFF00000D,
  );

  TextNote note(
    String id,
    String excerpt, {
    bool placed = true,
    String text = 'Una nota',
    TextNoteOrigin origin = TextNoteOrigin.note,
  }) {
    final start = content.indexOf(excerpt);
    return TextNote(
      id: id,
      origin: origin,
      target: target,
      start: placed ? start : null,
      end: placed ? start + excerpt.length : null,
      excerpt: excerpt,
      note: text,
      color: HighlightColor.violet,
      renditionId: 'rend',
      createdAt: DateTime(2026, 10, 30),
      updatedAt: DateTime(2026, 10, 30),
    );
  }

  group('buildDocumentNotes', () {
    test('las que caen en el texto, en su orden, con el color de la línea de '
        'su color; la que ya no está, afuera', () {
      final notes = buildDocumentNotes(
        content: content,
        textKey: 'rend',
        notes: [
          note('b', 'tablas', text: 'Segunda'),
          note('a', 'monte', text: 'Primera'),
          note('perdida', 'el becerro', placed: false),
          // Sin lugar guardado, pero su pedazo está: vuelve.
          note('vuelve', 'ley', placed: false, text: 'Tercera'),
        ],
        colors: colors,
      );

      expect(
        [for (final n in notes) n.note],
        ['Primera', 'Segunda', 'Tercera'],
      );
      final first = notes.first;
      expect(content.substring(first.start, first.end), 'monte');
      expect(first.excerpt, 'monte');
      expect(first.color, 0xFF0000B1);
    });

    test('«Mis notas» se ofrece solo si alguna cae en el texto', () {
      MarkedDocumentOptions available(List<TextNote> notes) =>
          availableMarkedOptions(
            content: content,
            study: DocumentStudy.notStarted,
            highlights: const [],
            notes: notes,
            textKey: 'rend',
          );

      expect(available(const []).myNotes, isFalse);
      expect(
        available([note('x', 'el becerro', placed: false)]).myNotes,
        isFalse,
      );
      expect(available([note('a', 'monte')]).myNotes, isTrue);
    });

    test('el nombre del archivo lo dice', () {
      expect(
        const MarkedDocumentOptions(
          myHighlights: true,
          myNotes: true,
        ).fileLabel,
        'mis resaltados y mis notas',
      );
      expect(const MarkedDocumentOptions(myNotes: true).isEmpty, isFalse);
    });

    test('con «Mis notas», la nota de un resaltado de antes no se repite en '
        'el resaltado', () {
      final start = content.indexOf('monte');
      final highlight = Highlight(
        id: 'r1',
        renditionId: 'rend',
        startOffset: start,
        endOffset: start + 5,
        excerpt: 'monte',
        createdAt: DateTime(2026, 10, 30),
        note: 'Vieja',
        color: HighlightColor.violet,
      );
      List<String?> notesOf(MarkedDocumentOptions options) => [
        for (final mark in buildDocumentMarks(
          content: content,
          options: options,
          study: DocumentStudy.notStarted,
          highlights: [highlight],
          colors: colors,
        ))
          mark.note,
      ];

      expect(notesOf(const MarkedDocumentOptions(myHighlights: true)), [
        'Vieja',
      ]);
      expect(
        notesOf(const MarkedDocumentOptions(myHighlights: true, myNotes: true)),
        [null],
      );
      expect(
        buildDocumentMarks(
          content: content,
          options: const MarkedDocumentOptions(myHighlights: true),
          study: DocumentStudy.notStarted,
          highlights: [highlight],
          colors: colors,
        ).single.style,
        HighlightStyle.fill,
      );
    });
  });

  group('el caso de uso', () {
    late InMemoryFileStore files;
    late FakeMarkedDocumentWriter writer;

    setUp(() {
      files = InMemoryFileStore();
      writer = FakeMarkedDocumentWriter();
    });

    Future<DownloadMarkedDocumentParams> params(
      MarkedDocumentOptions options,
      List<TextNote> notes,
    ) async {
      final path = await files.save(
        bytes: Uint8List.fromList(utf8.encode('# Éxodo\n\n$content')),
        suggestedName: 'exodo.md',
        id: 'item-1',
      );
      final item = sampleKnowledgeItem(title: 'Éxodo');
      return DownloadMarkedDocumentParams(
        item: item.copyWith(
          source: item.source.copyWith(
            kind: SourceKind.document,
            originalFilePath: path,
          ),
        ),
        content: content,
        study: DocumentStudy.notStarted,
        highlights: const [],
        options: options,
        notes: notes,
        textKey: 'rend',
      );
    }

    DownloadMarkedDocumentUseCase build() => DownloadMarkedDocumentUseCase(
      files: files,
      writers: {MarkedDocumentFormat.markdown: writer},
      saver: FakeFileSaver(),
      colors: colors,
    );

    test('solo con notas, llegan al escritor, y el archivo lo dice', () async {
      final result = await build()(
        await params(const MarkedDocumentOptions(myNotes: true), [
          note('a', 'monte', text: 'Sinaí'),
        ]),
      );

      expect(result.isRight(), isTrue);
      expect(writer.lastMarks, isEmpty);
      expect([for (final n in writer.lastNotes!) n.note], ['Sinaí']);
      expect(result.getRight().toNullable()!.fileName, 'Éxodo — mis notas.md');
    });

    test(
      'sin «Mis notas», no van; y si ninguna cae, no hay nada que marcar',
      () async {
        final without = await build()(
          await params(const MarkedDocumentOptions(keywords: true), [
            note('a', 'monte'),
          ]),
        );
        expect(
          without.getLeft().toNullable()!.error,
          MarkedDownloadError.nothingToMark,
        );
        expect(writer.calls, 0);

        final none = await build()(
          await params(const MarkedDocumentOptions(myNotes: true), [
            note('x', 'el becerro', placed: false),
          ]),
        );
        expect(
          none.getLeft().toNullable()!.error,
          MarkedDownloadError.nothingToMark,
        );
      },
    );
  });
}
