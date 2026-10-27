import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_source_material.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_triage.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/services/triage_offer.dart';

/// Lo que se elige en la hoja «¿Qué va a Procesado?» (F41), sin pantalla: qué
/// pedido arma para `ProcessSourceUseCase` y el contrato con «Volver a triar».
void main() {
  const anchor = ProcessedAnchor(renditionId: 'r', start: 0, end: 10);
  const other = ProcessedAnchor(renditionId: 'r', start: 20, end: 30);
  const elsewhere = ProcessedAnchor(renditionId: 'otra', start: 0, end: 10);
  const empty = ProcessedTriage(sourceItemId: 'fuente');

  group('la forma de cada sección', () {
    test('lo de la fuente se prende entero; lo tuyo es una lista', () {
      expect(
        {
          for (final section in ProcessedSection.values)
            section: triageShapeOf(section),
        },
        {
          ProcessedSection.text: TriageSectionShape.whole,
          ProcessedSection.summary: TriageSectionShape.whole,
          ProcessedSection.synthesis: TriageSectionShape.whole,
          ProcessedSection.keywords: TriageSectionShape.whole,
          ProcessedSection.notes: TriageSectionShape.clips,
          ProcessedSection.fragments: TriageSectionShape.clips,
        },
      );
    });
  });

  group('el pedido', () {
    test('sin nada elegido, no pide nada', () {
      expect(empty.edits, isEmpty);
      expect(empty.isEmpty, isTrue);
      expect(empty.documentExists, isFalse);
    });

    test('un documento con secciones vacías todavía no existe', () {
      expect(
        const ProcessedTriage(
          sourceItemId: 'fuente',
          existing: {ProcessedSection.summary: 0},
        ).documentExists,
        isFalse,
      );
      expect(
        const ProcessedTriage(
          sourceItemId: 'fuente',
          existing: {ProcessedSection.summary: 0, ProcessedSection.text: 2},
        ).documentExists,
        isTrue,
      );
    });

    test('una sección entera prendida pide agregarla desde la fuente', () {
      final triage = empty
          .withSection(ProcessedSection.text, on: true)
          .withSection(ProcessedSection.synthesis, on: true);

      expect(triage.edits, {
        ProcessedSection.text: SectionEdit.add(const SectionInput.fromSource()),
        ProcessedSection.synthesis: SectionEdit.add(
          const SectionInput.fromSource(),
        ),
      });
    });

    test('apagarla la saca del pedido', () {
      final triage = empty
          .withSection(ProcessedSection.text, on: true)
          .withSection(ProcessedSection.text, on: false);

      expect(triage.edits, isEmpty);
      expect(triage.includes(ProcessedSection.text), isFalse);
    });

    test('cada cambio de una sección entera es el suyo', () {
      ProcessedTriage withChange(ProcessedChange change) =>
          empty.withChange(ProcessedSection.summary, change);

      expect(
        withChange(ProcessedChange.update).edits[ProcessedSection.summary],
        SectionEdit.update(),
      );
      expect(
        withChange(ProcessedChange.replace).edits[ProcessedSection.summary],
        SectionEdit.replace(const SectionInput.fromSource()),
      );
      expect(
        withChange(ProcessedChange.remove).edits[ProcessedSection.summary],
        SectionEdit.remove(),
      );
    });

    test('las notas y los fragmentos piden sus pasajes, en el orden en que '
        'se eligieron', () {
      final triage = empty
          .withClip(
            ProcessedSection.fragments,
            const ProcessedDraft.cut(other),
            excerpt: 'b',
          )
          .withClip(
            ProcessedSection.fragments,
            const ProcessedDraft.cut(anchor),
            excerpt: 'a',
          )
          .withClip(
            ProcessedSection.notes,
            const ProcessedDraft.written('Mi nota'),
            excerpt: 'Mi nota',
          );

      expect(triage.edits, {
        ProcessedSection.fragments: SectionEdit.add(
          const SectionInput.drafts([
            ProcessedDraft.cut(other),
            ProcessedDraft.cut(anchor),
          ]),
        ),
        ProcessedSection.notes: SectionEdit.add(
          const SectionInput.drafts([ProcessedDraft.written('Mi nota')]),
        ),
      });
    });

    test('cada pedido que arma vale para su sección', () {
      final triage = empty
          .withSection(ProcessedSection.text, on: true)
          .withChange(ProcessedSection.summary, ProcessedChange.update)
          .withClip(
            ProcessedSection.fragments,
            const ProcessedDraft.cut(anchor),
            excerpt: 'a',
          );

      for (final MapEntry(key: section, value: edit) in triage.edits.entries) {
        expect(edit.problemFor(section), isNull, reason: section.name);
      }
    });

    test('una lista prendida sin pasajes no pide nada; actualizarla tampoco: '
        'no hay versión en la fuente', () {
      expect(
        empty.withSection(ProcessedSection.notes, on: true).edits,
        isEmpty,
      );
      expect(
        empty
            .withClip(
              ProcessedSection.notes,
              const ProcessedDraft.written('x'),
              excerpt: 'x',
            )
            .withChange(ProcessedSection.notes, ProcessedChange.update)
            .edits,
        isEmpty,
      );
    });

    test('quitar una lista entera se pide aunque no lleve pasajes', () {
      expect(
        empty
            .withChange(ProcessedSection.fragments, ProcessedChange.remove)
            .edits,
        {ProcessedSection.fragments: SectionEdit.remove()},
      );
    });
  });

  group('los pasajes', () {
    test('el mismo corte no entra dos veces: devuelve la misma hoja', () {
      final once = empty.withClip(
        ProcessedSection.fragments,
        const ProcessedDraft.cut(anchor),
        excerpt: 'a',
      );
      final twice = once.withClip(
        ProcessedSection.fragments,
        const ProcessedDraft.cut(anchor),
        excerpt: 'a',
      );

      expect(identical(once, twice), isTrue);
      expect(twice.clipsOf(ProcessedSection.fragments), hasLength(1));
    });

    test('el mismo tramo puede ser nota y fragmento a la vez', () {
      final triage = empty
          .withClip(
            ProcessedSection.fragments,
            const ProcessedDraft.cut(anchor),
            excerpt: 'a',
          )
          .withClip(
            ProcessedSection.notes,
            const ProcessedDraft.cut(anchor),
            excerpt: 'a',
          );

      expect(triage.clipsOf(ProcessedSection.fragments), hasLength(1));
      expect(triage.clipsOf(ProcessedSection.notes), hasLength(1));
    });

    test('cada pasaje tiene su id, y quitarlo saca solo ese', () {
      final triage = empty
          .withClip(
            ProcessedSection.fragments,
            const ProcessedDraft.cut(anchor),
            excerpt: 'a',
          )
          .withClip(
            ProcessedSection.fragments,
            const ProcessedDraft.cut(other),
            excerpt: 'b',
          );
      final [first, second] = triage.clipsOf(ProcessedSection.fragments);
      expect(first.id, isNot(second.id));

      final left = triage.withoutClip(first.id);

      expect(left.clipsOf(ProcessedSection.fragments), [second]);
    });

    test('una lista que se vacía deja de ir', () {
      final triage = empty.withClip(
        ProcessedSection.notes,
        const ProcessedDraft.written('x'),
        excerpt: 'x',
      );
      final clip = triage.clipsOf(ProcessedSection.notes).single;

      final left = triage.withoutClip(clip.id);

      expect(left.includes(ProcessedSection.notes), isFalse);
      expect(left.edits, isEmpty);
    });

    test('sumarle algo a una lista que se iba a quitar es reemplazarla', () {
      final triage = empty
          .withChange(ProcessedSection.notes, ProcessedChange.remove)
          .withClip(
            ProcessedSection.notes,
            const ProcessedDraft.written('Otra'),
            excerpt: 'Otra',
          );

      expect(
        triage.edits[ProcessedSection.notes],
        SectionEdit.replace(
          const SectionInput.drafts([ProcessedDraft.written('Otra')]),
        ),
      );
    });

    test('lo que se marca en un texto son los cortes de ese texto, no las '
        'notas ni los de otro', () {
      final triage = empty
          .withClip(
            ProcessedSection.fragments,
            const ProcessedDraft.cut(anchor),
            excerpt: 'a',
          )
          .withClip(
            ProcessedSection.fragments,
            const ProcessedDraft.cut(elsewhere),
            excerpt: 'c',
          )
          .withClip(
            ProcessedSection.notes,
            const ProcessedDraft.cut(other),
            excerpt: 'b',
          );

      expect(triage.cutsIn('r'), [anchor]);
      expect(triage.cutsIn('otra'), [elsewhere]);
      expect(triage.cutsIn('ninguna'), isEmpty);
    });
  });

  group('el contrato con «Volver a triar» (paso 4)', () {
    test('nace de lo que el documento tiene y de un pedido, y lo devuelve '
        'igual', () {
      final edits = {
        ProcessedSection.summary: SectionEdit.update(),
        ProcessedSection.notes: SectionEdit.replace(
          const SectionInput.drafts([
            ProcessedDraft.written('Una'),
            ProcessedDraft.cut(anchor),
          ]),
        ),
        ProcessedSection.text: SectionEdit.remove(),
      };

      final triage = ProcessedTriage.from(
        'fuente',
        existing: const {ProcessedSection.summary: 4},
        edits: edits,
        excerptOf: (anchor) => 'del original',
      );

      expect(triage.documentExists, isTrue);
      expect(triage.edits, edits);
      expect(
        [
          for (final clip in triage.clipsOf(ProcessedSection.notes))
            clip.excerpt,
        ],
        ['Una', 'del original'],
      );
    });

    test('los pasajes sin texto se completan después, sin tocar los demás', () {
      final triage = ProcessedTriage.from(
        'fuente',
        edits: {
          ProcessedSection.fragments: SectionEdit.add(
            const SectionInput.drafts([
              ProcessedDraft.cut(anchor),
              ProcessedDraft.cut(other),
            ]),
          ),
        },
        excerptOf: (a) => a == other ? 'ya se sabía' : '',
      );

      final filled = triage.withExcerpts({anchor: 'leído', other: 'otro'});

      expect(
        [
          for (final clip in filled.clipsOf(ProcessedSection.fragments))
            clip.excerpt,
        ],
        ['leído', 'ya se sabía'],
      );
      expect(filled.edits, triage.edits);
    });

    test('los ids de los pasajes que trae no chocan con los que se sumen', () {
      final triage =
          ProcessedTriage.from(
            'fuente',
            edits: {
              ProcessedSection.notes: SectionEdit.add(
                const SectionInput.drafts([ProcessedDraft.written('Una')]),
              ),
            },
          ).withClip(
            ProcessedSection.notes,
            const ProcessedDraft.written('Otra'),
            excerpt: 'Otra',
          );

      final ids = [
        for (final clip in triage.clipsOf(ProcessedSection.notes)) clip.id,
      ];
      expect(ids.toSet(), hasLength(2));
    });
  });

  group('lo que ofrece la fuente', () {
    ProcessedSourceMaterial material({bool text = true}) =>
        ProcessedSourceMaterial(
          sourceItemId: 'fuente',
          title: 'Roma',
          sourceKind: SourceKind.document,
          textRenditionId: text ? 'r' : null,
          textCharacters: text ? 100 : 0,
        );

    test('con texto, todas las secciones, en el orden en que se leen', () {
      expect(triageSectionsOffered(material()), ProcessedSection.values);
    });

    test('sin texto propio, solo escribir notas', () {
      expect(triageSectionsOffered(material(text: false)), [
        ProcessedSection.notes,
      ]);
    });
  });
}
