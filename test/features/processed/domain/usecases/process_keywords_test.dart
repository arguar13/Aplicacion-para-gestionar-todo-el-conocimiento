import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';

import '../../processed_harness.dart';

/// Las palabras clave en un documento procesado (ajuste del dueño): cada parte,
/// una oración con sus palabras adentro, con las mismas reglas que el resumen y
/// la síntesis.
void main() {
  const text =
      'La revolución industrial empezó en Inglaterra. '
      'El vapor movió las fábricas. Nada más.';
  late ProcessedHarness h;
  final docId = processedDocumentIdFor('libro');

  setUp(() async {
    h = await ProcessedHarness.create();
    await h.vault.saveSource('libro', text: text);
  });
  tearDown(() => h.close());

  Future<void> keyword(String id, String word) {
    final start = text.indexOf(word);
    return h.addSentence(
      id,
      'libro',
      text,
      start: start,
      end: start + word.length,
      kind: StudyMarkKind.keyword,
    );
  }

  Future<List<ProcessedPart>> parts() async => (await h.repository.partsOf(
    docId,
    sections: {ProcessedSection.keywords},
  )).getRight().toNullable()!;

  test(
    'la fuente las ofrece por oración, en orden, con cada palabra',
    () async {
      await keyword('k3', 'fábricas');
      await keyword('k1', 'revolución');
      await keyword('k2', 'Inglaterra');

      final material = (await h.repository.materialOf(
        'libro',
        countWords: false,
      )).getRight().toNullable()!;

      expect(material.keywords.map((s) => s.content), [
        'La revolución industrial empezó en Inglaterra.',
        'El vapor movió las fábricas.',
      ]);
      expect(
        material.keywords.first.keywords.map((k) => (k.studyMarkId, k.word)),
        [('k1', 'revolución'), ('k2', 'Inglaterra')],
      );
      expect(material.keywords.last.anchor.start, text.indexOf('El vapor'));
    },
  );

  test('entran las oraciones con sus palabras, y con una elección, solo esas '
      'palabras', () async {
    await keyword('k1', 'revolución');
    await keyword('k2', 'Inglaterra');
    await keyword('k3', 'fábricas');

    await h.process('libro', {
      ProcessedSection.keywords: SectionEdit.add(
        const SectionInput.sentences({'k2', 'k3'}),
      ),
    });

    final kept = await parts();
    expect(kept.map((p) => p.keywords), [
      ['Inglaterra'],
      ['fábricas'],
    ]);
    expect(kept.first.spans.single.start, text.indexOf('Inglaterra'));
    expect(kept.first.anchor?.start, 0);
    expect(kept.first.origin, ProcessedPartOrigin.copied);
  });

  test('una palabra que no es de la fuente no entra', () async {
    await keyword('k1', 'revolución');

    final result = await h.process('libro', {
      ProcessedSection.keywords: SectionEdit.add(
        const SectionInput.sentences({'k1', 'otra'}),
      ),
    });

    expect(result.getLeft().toNullable(), isA<ValidationFailure>());
  });

  test('actualizar trae las palabras de ahora; la oración igual es la misma '
      'parte, y una con otras palabras se renueva', () async {
    await keyword('k1', 'revolución');
    await keyword('k3', 'fábricas');
    await h.process('libro', {
      ProcessedSection.keywords: SectionEdit.add(
        const SectionInput.fromSource(),
      ),
    });
    final before = await parts();
    await keyword('k4', 'vapor');

    await h.process('libro', {ProcessedSection.keywords: SectionEdit.update()});

    final after = await parts();
    expect(after.first.id, before.first.id);
    expect(after.last.id, isNot(before.last.id));
    expect(after.last.keywords, ['vapor', 'fábricas']);
  });

  test('editada, una oración pierde su lugar en el texto propio', () async {
    await keyword('k1', 'revolución');
    await h.process('libro', {
      ProcessedSection.text: SectionEdit.update(),
      ProcessedSection.keywords: SectionEdit.add(
        const SectionInput.fromSource(),
      ),
    });
    final sentence = (await parts()).single;
    expect(sentence.textRange, isNotNull);

    await h.repository.editPart(sentence.id, 'La revolución, editada.');

    expect((await parts()).single.textRange, isNull);
  });

  test('una palabra repetida se busca después de la anterior', () async {
    await h.vault.saveSource('roma', text: 'Roma y más Roma. Fin.');
    final id = processedDocumentIdFor('roma');
    for (final (mark, start) in [('a', 0), ('b', 11)]) {
      await h.addSentence(
        mark,
        'roma',
        'Roma y más Roma. Fin.',
        start: start,
        end: start + 4,
        kind: StudyMarkKind.keyword,
      );
    }
    await h.process('roma', {
      ProcessedSection.keywords: SectionEdit.add(
        const SectionInput.fromSource(),
      ),
    });
    final sentence = (await h.repository.partsOf(
      id,
      sections: {ProcessedSection.keywords},
    )).getRight().toNullable()!.single;

    await h.repository.editPart(sentence.id, 'Roma, y Roma otra vez.');

    final edited = (await h.repository.partsOf(
      id,
      sections: {ProcessedSection.keywords},
    )).getRight().toNullable()!.single;
    expect([for (final s in edited.spans) s.start], [0, 8]);
  });

  test('editar la oración lleva sus palabras a donde quedaron; la que ya no '
      'está se va', () async {
    await keyword('k1', 'revolución');
    await keyword('k2', 'Inglaterra');
    await h.process('libro', {
      ProcessedSection.keywords: SectionEdit.add(
        const SectionInput.fromSource(),
      ),
    });
    final sentence = (await parts()).first;

    await h.repository.editPart(
      sentence.id,
      'Empezó la revolución, de a poco.',
    );

    final edited = (await parts()).first;
    expect(edited.keywords, ['revolución']);
    expect(edited.spans.single.start, 'Empezó la '.length);
    expect(edited.edited, isTrue);
    // Editada, ya no se marca sobre el original: no es la letra de la fuente.
    expect(edited.isVerbatim, isFalse);
  });
}
