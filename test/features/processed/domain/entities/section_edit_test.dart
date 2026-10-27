import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';

/// Qué se le puede pedir a cada sección (F41).
void main() {
  const anchor = ProcessedAnchor(renditionId: 'r', start: 0, end: 4);
  const cut = ProcessedDraft.cut(anchor);
  const note = ProcessedDraft.written('Una idea.');

  bool allowed(ProcessedSection section, SectionEdit edit) =>
      edit.problemFor(section) == null;

  test('el texto, el resumen y la síntesis salen de la fuente, y se '
      'actualizan', () {
    for (final section in [
      ProcessedSection.text,
      ProcessedSection.summary,
      ProcessedSection.synthesis,
    ]) {
      expect(section.canUpdate, isTrue);
      expect(allowed(section, SectionEdit.update()), isTrue);
      expect(
        allowed(section, SectionEdit.add(const SectionInput.fromSource())),
        isTrue,
      );
      expect(
        allowed(section, SectionEdit.replace(const SectionInput.fromSource())),
        isTrue,
      );
      expect(
        allowed(section, SectionEdit.add(const SectionInput.drafts([cut]))),
        isFalse,
        reason: 'no se cortan a mano',
      );
    }
  });

  test('las oraciones elegidas, solo en el resumen y la síntesis', () {
    const some = SectionInput.sentences({'m1'});
    expect(allowed(ProcessedSection.summary, SectionEdit.add(some)), isTrue);
    expect(allowed(ProcessedSection.synthesis, SectionEdit.add(some)), isTrue);
    expect(allowed(ProcessedSection.text, SectionEdit.add(some)), isFalse);
    expect(allowed(ProcessedSection.notes, SectionEdit.add(some)), isFalse);
    expect(
      allowed(
        ProcessedSection.summary,
        SectionEdit.add(const SectionInput.sentences({})),
      ),
      isFalse,
    );
  });

  test('las notas y los fragmentos no tienen versión en la fuente', () {
    for (final section in [
      ProcessedSection.notes,
      ProcessedSection.fragments,
    ]) {
      expect(section.canUpdate, isFalse);
      expect(allowed(section, SectionEdit.update()), isFalse);
      expect(
        allowed(section, SectionEdit.add(const SectionInput.fromSource())),
        isFalse,
      );
    }
  });

  test('una nota se escribe o se extrae; un fragmento solo se corta', () {
    expect(
      allowed(
        ProcessedSection.notes,
        SectionEdit.add(const SectionInput.drafts([note, cut])),
      ),
      isTrue,
    );
    expect(
      allowed(
        ProcessedSection.fragments,
        SectionEdit.add(const SectionInput.drafts([cut])),
      ),
      isTrue,
    );
    expect(
      allowed(
        ProcessedSection.fragments,
        SectionEdit.add(const SectionInput.drafts([note])),
      ),
      isFalse,
    );
    expect(
      allowed(
        ProcessedSection.notes,
        SectionEdit.add(const SectionInput.drafts([])),
      ),
      isFalse,
    );
    expect(
      allowed(
        ProcessedSection.notes,
        SectionEdit.add(
          const SectionInput.drafts([ProcessedDraft.written('   ')]),
        ),
      ),
      isFalse,
    );
    for (final bad in [
      const ProcessedAnchor(renditionId: 'r', start: -1, end: 4),
      const ProcessedAnchor(renditionId: 'r', start: 4, end: 4),
    ]) {
      expect(
        allowed(
          ProcessedSection.fragments,
          SectionEdit.add(SectionInput.drafts([ProcessedDraft.cut(bad)])),
        ),
        isFalse,
      );
      expect(
        allowed(
          ProcessedSection.notes,
          SectionEdit.add(
            SectionInput.drafts([ProcessedDraft.written('x', anchor: bad)]),
          ),
        ),
        isFalse,
      );
    }
  });

  test('quitar no lleva nada, y agregar o reemplazar sí', () {
    for (final section in ProcessedSection.values) {
      expect(allowed(section, SectionEdit.remove()), isTrue);
      expect(
        allowed(
          section,
          const SectionEdit(
            change: ProcessedChange.remove,
            input: SectionInput.fromSource(),
          ),
        ),
        isFalse,
      );
      expect(
        allowed(section, const SectionEdit(change: ProcessedChange.add)),
        isFalse,
      );
      expect(
        allowed(section, const SectionEdit(change: ProcessedChange.replace)),
        isFalse,
      );
    }
    expect(
      allowed(
        ProcessedSection.text,
        const SectionEdit(
          change: ProcessedChange.update,
          input: SectionInput.sentences({'m'}),
        ),
      ),
      isFalse,
    );
  });

  test('un ancla se superpone solo en el mismo texto', () {
    expect(
      anchor.overlaps(
        const ProcessedAnchor(renditionId: 'r', start: 3, end: 9),
      ),
      isTrue,
    );
    expect(
      anchor.overlaps(
        const ProcessedAnchor(renditionId: 'r', start: 4, end: 9),
      ),
      isFalse,
    );
    // Tocarse en el borde no es superponerse, se mire de donde se mire.
    expect(
      const ProcessedAnchor(
        renditionId: 'r',
        start: 4,
        end: 9,
      ).overlaps(anchor),
      isFalse,
    );
    expect(
      anchor.overlaps(
        const ProcessedAnchor(renditionId: 'x', start: 0, end: 4),
      ),
      isFalse,
    );
  });

  test('una parte dice dónde está en el original solo si sigue siendo lo de '
      'la fuente', () {
    final at = DateTime(2026);
    final part = ProcessedPart(
      id: 'p',
      documentId: 'd',
      section: ProcessedSection.text,
      position: 0,
      content: 'abcdef',
      origin: ProcessedPartOrigin.copied,
      edited: false,
      createdAt: at,
      updatedAt: at,
      sourceRenditionId: 'r',
      sourceStart: 100,
      sourceEnd: 106,
    );

    expect(part.sourceOffsetOf(2), 102);
    expect(part.sourceOffsetOf(6), 106);
    expect(part.sourceOffsetOf(7), isNull);
    expect(part.sourceOffsetOf(-1), isNull);
    expect(part.copyWith(edited: true).sourceOffsetOf(2), isNull);
    expect(part.copyWith(sourceRenditionId: null).sourceOffsetOf(2), isNull);
    expect(part.copyWith(sourceRenditionId: null).anchor, isNull);
    expect(
      part.copyWith(origin: ProcessedPartOrigin.user).isPristineCopy,
      isFalse,
    );
  });
}
