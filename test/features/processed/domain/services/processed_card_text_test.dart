import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/services/processed_card_text.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/domain/services/processed_text.dart';

import '../../processed_harness.dart';

final _at = DateTime(2026, 10, 28);

ProcessedPart _part(
  String id,
  ProcessedSection section,
  int position,
  String content, {
  int? sourceStart,
  bool edited = false,
}) => ProcessedPart(
  id: id,
  documentId: 'doc',
  section: section,
  position: position,
  content: content,
  origin: section == ProcessedSection.notes
      ? ProcessedPartOrigin.user
      : ProcessedPartOrigin.copied,
  edited: edited,
  createdAt: _at,
  updatedAt: _at,
  sourceRenditionId: sourceStart == null ? null : 'rend',
  sourceStart: sourceStart,
  sourceEnd: sourceStart == null ? null : sourceStart + content.length,
);

/// El texto con el que se estudia un documento procesado (F41, decisión I):
/// lo que leen sus tarjetas y su cobertura.
void main() {
  group('buildProcessedCardText', () {
    test('las partes en el orden en que se leen, separadas por un renglón en '
        'blanco, sin las que están en blanco', () {
      final text = buildProcessedCardText('doc', [
        _part('n0', ProcessedSection.notes, 0, 'Una nota.'),
        _part('t1', ProcessedSection.text, 1, 'Segunda página.'),
        _part('s0', ProcessedSection.summary, 0, '   '),
        _part('t0', ProcessedSection.text, 0, 'Primera página.'),
        _part('f0', ProcessedSection.fragments, 0, 'Un pasaje.'),
      ])!;

      expect(
        text.content,
        'Primera página.\n\nSegunda página.\n\nUna nota.\n\nUn pasaje.',
      );
      expect(text.documentId, 'doc');
      expect(
        [for (final s in text.segments) s.partId],
        ['t0', 't1', 'n0', 'f0'],
      );
      for (final segment in text.segments) {
        final part = {
          't0': 'Primera página.',
          't1': 'Segunda página.',
          'n0': 'Una nota.',
          'f0': 'Un pasaje.',
        }[segment.partId];
        expect(text.content.substring(segment.start, segment.end), part);
      }
    });

    test('sin nada que estudiar, no hay texto', () {
      expect(buildProcessedCardText('doc', const []), isNull);
      expect(
        buildProcessedCardText('doc', [
          _part('t0', ProcessedSection.text, 0, ' \n '),
        ]),
        isNull,
      );
    });

    test('las tarjetas salen de todas las secciones de hoy, también de las '
        'palabras clave', () {
      expect(cardSections, ProcessedSection.values);
      expect(isCardSection(ProcessedSection.keywords), isTrue);
    });

    test('un procesado con solo palabras clave tiene texto para tarjetas, en '
        'su lugar entre el resumen y las notas', () {
      final text = buildProcessedCardText('doc', [
        _part('n0', ProcessedSection.notes, 0, 'Una nota.'),
        _part('k0', ProcessedSection.keywords, 0, 'El Senado legislaba.'),
        _part('s0', ProcessedSection.summary, 0, 'Lo principal.'),
      ])!;

      expect(
        text.content,
        'Lo principal.\n\nEl Senado legislaba.\n\nUna nota.',
      );
      expect(
        buildProcessedCardText('doc', [
          _part('k0', ProcessedSection.keywords, 0, 'El Senado legislaba.'),
        ])!.content,
        'El Senado legislaba.',
      );
    });
  });

  group('sourceAnchorOf', () {
    final text = buildProcessedCardText('doc', [
      _part(
        't0',
        ProcessedSection.text,
        0,
        'Roma fue fundada.',
        sourceStart: 100,
      ),
      _part(
        't1',
        ProcessedSection.text,
        1,
        'El Senado.',
        sourceStart: 200,
        edited: true,
      ),
      _part('n0', ProcessedSection.notes, 0, 'Lo que pienso.'),
      _part(
        'f0',
        ProcessedSection.fragments,
        0,
        'Los cónsules.',
        sourceStart: 300,
      ),
    ])!;

    int at(String needle) => text.content.indexOf(needle);

    test('lo copiado intacto lleva a su lugar en el original', () {
      final start = at('fundada');
      expect(
        text.sourceAnchorOf(start, start + 'fundada'.length),
        const ProcessedAnchor(renditionId: 'rend', start: 109, end: 116),
      );
      final last = at('cónsules');
      expect(
        text.sourceAnchorOf(last, last + 'cónsules'.length),
        const ProcessedAnchor(renditionId: 'rend', start: 304, end: 312),
      );
    });

    test('lo editado, lo escrito, lo que cruza dos partes o se sale del texto, '
        'no', () {
      final edited = at('Senado');
      expect(text.sourceAnchorOf(edited, edited + 6), isNull);
      final note = at('pienso');
      expect(text.sourceAnchorOf(note, note + 6), isNull);
      expect(text.sourceAnchorOf(at('fundada'), at('Senado') + 3), isNull);
      expect(text.sourceAnchorOf(-1, 3), isNull);
      expect(text.sourceAnchorOf(3, 3), isNull);
      expect(text.sourceAnchorOf(0, text.content.length + 1), isNull);
      // Entre dos partes, en el renglón en blanco.
      final gap = text.segments.first.end;
      expect(text.sourceAnchorOf(gap, gap + 1), isNull);
    });
  });

  group('readProcessedCardText', () {
    late ProcessedHarness h;

    setUp(() async {
      h = await ProcessedHarness.create();
    });
    tearDown(() => h.close());

    test('lee las partes del procesado, no la fuente; de lo que no es un '
        'procesado no hay texto', () async {
      await h.vault.saveSource('roma', text: 'Roma fue fundada.');
      expect((await h.process.passUnchanged('roma')).isRight(), isTrue);
      final docId = processedDocumentIdFor('roma');
      final page = (await h.repository.partsOf(
        docId,
      )).getRight().toNullable()!.single;
      await h.repository.editPart(page.id, 'Cartago fue destruida.');
      await h.process('roma', {
        ProcessedSection.notes: SectionEdit.add(
          const SectionInput.drafts([ProcessedDraft.written('Aníbal.')]),
        ),
      });

      final text = (await readProcessedCardText(
        h.repository,
        docId,
      )).getRight().toNullable()!;

      expect(text.content, 'Cartago fue destruida.\n\nAníbal.');
      final ofSource = await readProcessedCardText(h.repository, 'roma');
      expect(ofSource.isRight(), isTrue);
      expect(ofSource.getRight().toNullable(), isNull);
    });

    test('un libro entero se junta en otro hilo y da lo mismo', () async {
      final book = List.filled(
        kProcessedInlineChars ~/ 20 + 10,
        'Una frase del libro. ',
      ).join();
      await h.vault.saveSource('libro', text: book);
      expect((await h.process.passUnchanged('libro')).isRight(), isTrue);
      final docId = processedDocumentIdFor('libro');
      final parts = (await h.repository.partsOf(
        docId,
      )).getRight().toNullable()!;

      final text = (await readProcessedCardText(
        h.repository,
        docId,
      )).getRight().toNullable()!;

      expect(parts.length, greaterThan(1));
      expect(text.content, buildProcessedCardText(docId, parts)!.content);
      expect(text.content.length, greaterThanOrEqualTo(kProcessedInlineChars));
      expect(text.segments, hasLength(parts.length));
    });
  });
}
