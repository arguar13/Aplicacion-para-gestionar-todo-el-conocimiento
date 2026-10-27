import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/services/processed_section_planner.dart';

/// Las reglas de agregar, actualizar, reemplazar y quitar una sección de un
/// documento procesado (F41): puras, sin base.
void main() {
  final at = DateTime(2026, 10, 27);

  ProcessedAnchor a(int start, int end, [String rendition = 'r']) =>
      ProcessedAnchor(renditionId: rendition, start: start, end: end);

  var counter = 0;
  ProcessedPart part(
    String content, {
    ProcessedAnchor? anchor,
    bool edited = false,
    ProcessedPartOrigin origin = ProcessedPartOrigin.copied,
    int? position,
    String? id,
  }) => ProcessedPart(
    id: id ?? 'p${counter++}',
    documentId: 'doc',
    section: ProcessedSection.summary,
    position: position ?? counter,
    content: content,
    origin: origin,
    edited: edited,
    createdAt: at,
    updatedAt: at,
    sourceRenditionId: anchor?.renditionId,
    sourceStart: anchor?.start,
    sourceEnd: anchor?.end,
  );

  ProcessedCandidate copy(String content, ProcessedAnchor anchor) =>
      ProcessedCandidate(
        content: content,
        origin: ProcessedPartOrigin.copied,
        anchor: anchor,
      );

  List<String> contents(SectionPlan plan) => plan.contents;

  group('quitar', () {
    test('saca todo', () {
      final existing = [part('A', anchor: a(0, 1)), part('B')];

      final plan = planSectionChange(
        section: ProcessedSection.summary,
        existing: existing,
        change: ProcessedChange.remove,
      );

      expect(plan.parts, isEmpty);
      expect(plan.removed, existing);
      expect(plan.isNoOp, isFalse);
    });

    test('sobre una sección vacía no cambia nada', () {
      final plan = planSectionChange(
        section: ProcessedSection.summary,
        existing: const [],
        change: ProcessedChange.remove,
      );

      expect(plan.isNoOp, isTrue);
    });
  });

  group('reemplazar', () {
    test('saca todo y pone lo nuevo, sin repetir entre sí', () {
      final existing = [part('A', anchor: a(0, 1))];

      final plan = planSectionChange(
        section: ProcessedSection.summary,
        existing: existing,
        change: ProcessedChange.replace,
        fresh: [copy('X', a(5, 6)), copy('X', a(5, 6)), copy('Y', a(7, 8))],
      );

      expect(contents(plan), ['X', 'Y']);
      expect(plan.removed, existing);
      expect(plan.added, 2);
    });
  });

  group('agregar', () {
    test('suma lo que no está, por tramo o por texto', () {
      final existing = [part('Una idea.', anchor: a(0, 9))];

      final plan = planSectionChange(
        section: ProcessedSection.summary,
        existing: existing,
        change: ProcessedChange.add,
        fresh: [
          copy('Otra cosa', a(0, 9)), // el mismo tramo
          copy('  una   IDEA. ', a(20, 30)), // el mismo texto
          copy('Nueva.', a(40, 46)),
        ],
      );

      expect(contents(plan), ['Una idea.', 'Nueva.']);
      expect(plan.removed, isEmpty);
      expect(plan.kept, 1);
    });

    test('superponerse no es repetir', () {
      final plan = planSectionChange(
        section: ProcessedSection.fragments,
        existing: [part('abcdef', anchor: a(0, 6))],
        change: ProcessedChange.add,
        fresh: [copy('defgh', a(3, 8))],
      );

      expect(contents(plan), ['abcdef', 'defgh']);
    });

    test('en las páginas del texto repetir es solo el mismo tramo', () {
      final plan = planSectionChange(
        section: ProcessedSection.text,
        existing: [part('Igual', anchor: a(0, 5))],
        change: ProcessedChange.add,
        fresh: [copy('Igual', a(5, 10)), copy('Igual', a(0, 5))],
      );

      expect(contents(plan), ['Igual', 'Igual']);
      expect(plan.added, 1);
    });

    test('lo nuevo va en el orden del texto, entre lo que estaba', () {
      final plan = planSectionChange(
        section: ProcessedSection.summary,
        existing: [
          part('B', anchor: a(10, 11), position: 0),
          part('sin ancla', position: 1),
          part('D', anchor: a(30, 31), position: 2),
        ],
        change: ProcessedChange.add,
        fresh: [
          copy('E', a(40, 41)),
          copy('A', a(0, 1)),
          copy('C', a(20, 21)),
          copy('B2', a(10, 12)),
        ],
      );

      // Lo que se queda sin ancla sigue pegado a lo que tenía antes: lo nuevo
      // entra justo antes de la próxima parte con ancla que va después.
      expect(contents(plan), ['A', 'B', 'sin ancla', 'B2', 'C', 'D', 'E']);
    });

    test('lo que es de otro texto, o no tiene ancla, va al final', () {
      final plan = planSectionChange(
        section: ProcessedSection.summary,
        existing: [part('B', anchor: a(10, 11))],
        change: ProcessedChange.add,
        fresh: [
          const ProcessedCandidate(
            content: 'Suelta',
            origin: ProcessedPartOrigin.user,
          ),
          copy('Otro', a(0, 1, 'otra')),
        ],
      );

      expect(contents(plan), ['B', 'Otro', 'Suelta']);
    });

    test('las notas se suman al final, en el orden en que llegan', () {
      final plan = planSectionChange(
        section: ProcessedSection.notes,
        existing: [part('Vieja', anchor: a(50, 55))],
        change: ProcessedChange.add,
        fresh: [copy('Antes en el texto', a(0, 5)), copy('Otra', a(1, 2))],
      );

      expect(contents(plan), ['Vieja', 'Antes en el texto', 'Otra']);
    });
  });

  group('actualizar', () {
    test('lo copiado que la fuente sigue trayendo igual se queda —es la misma '
        'parte—, y lo que ya no trae se va', () {
      final igual = part('Igual.', anchor: a(0, 6), id: 'igual');
      final cambio = part('Vieja.', anchor: a(10, 16), id: 'cambio');
      final seFue = part('Se fue.', anchor: a(20, 27), id: 'sefue');

      final plan = planSectionChange(
        section: ProcessedSection.summary,
        existing: [igual, cambio, seFue],
        change: ProcessedChange.update,
        fresh: [copy('Igual.', a(0, 6)), copy('Nueva.', a(10, 16))],
      );

      expect(contents(plan), ['Igual.', 'Nueva.']);
      expect((plan.parts.first as KeptPart).part, igual);
      expect(plan.removed, [cambio, seFue]);
      expect(plan.added, 1);
    });

    test('lo editado se queda siempre, y lo nuevo que choca con ello no '
        'entra', () {
      final editada = part('Mía.', anchor: a(10, 20), edited: true);

      final plan = planSectionChange(
        section: ProcessedSection.summary,
        existing: [editada],
        change: ProcessedChange.update,
        fresh: [
          copy('Choca.', a(15, 25)),
          copy('Antes.', a(0, 10)),
          copy('Después.', a(20, 30)),
        ],
      );

      expect(contents(plan), ['Antes.', 'Mía.', 'Después.']);
      expect(plan.removed, isEmpty);
    });

    test('lo editado sin ancla se queda y no choca con nada', () {
      final editada = part('Mía.', edited: true);

      final plan = planSectionChange(
        section: ProcessedSection.summary,
        existing: [editada],
        change: ProcessedChange.update,
        fresh: [copy('Nueva.', a(0, 6))],
      );

      expect(contents(plan), ['Mía.', 'Nueva.']);
    });

    test('lo copiado cuyo texto ya no está se va', () {
      final huerfana = part('Huérfana.');

      final plan = planSectionChange(
        section: ProcessedSection.summary,
        existing: [huerfana],
        change: ProcessedChange.update,
        fresh: [copy('Huérfana.', a(0, 9))],
      );

      expect(plan.removed, [huerfana]);
      expect(contents(plan), ['Huérfana.']);
      expect(plan.added, 1);
    });

    test('lo que la persona escribió se queda', () {
      final nota = part('Mía.', origin: ProcessedPartOrigin.user);

      final plan = planSectionChange(
        section: ProcessedSection.summary,
        existing: [nota],
        change: ProcessedChange.update,
      );

      expect(plan.parts.single, isA<KeptPart>());
      expect(plan.removed, isEmpty);
    });

    test('sin cambios en la fuente, no cambia nada', () {
      final plan = planSectionChange(
        section: ProcessedSection.summary,
        existing: [
          part('A.', anchor: a(0, 2), position: 0),
          part('B.', anchor: a(3, 5), position: 1),
        ],
        change: ProcessedChange.update,
        fresh: [copy('A.', a(0, 2)), copy('B.', a(3, 5))],
      );

      expect(plan.isNoOp, isTrue);
    });
  });

  group('lo propio del procesado y las palabras clave (decisión I)', () {
    test('lo estudiado o elegido en el procesado se queda al actualizar, y lo '
        'de la fuente que se le superpone no entra', () {
      final studied = part(
        'Mía de la IA.',
        anchor: a(0, 13),
        origin: ProcessedPartOrigin.studied,
      );
      final chosen = part(
        'Elegida.',
        anchor: a(20, 28),
        origin: ProcessedPartOrigin.chosen,
      );

      final plan = planSectionChange(
        section: ProcessedSection.summary,
        existing: [studied, chosen],
        change: ProcessedChange.update,
        fresh: [copy('Choca.', a(5, 15)), copy('Nueva.', a(40, 46))],
      );

      expect(contents(plan), ['Mía de la IA.', 'Elegida.', 'Nueva.']);
      expect(plan.removed, isEmpty);
    });

    test('«Reemplazar» sí lo pisa', () {
      final studied = part(
        'Mía.',
        anchor: a(0, 4),
        origin: ProcessedPartOrigin.studied,
      );

      final plan = planSectionChange(
        section: ProcessedSection.summary,
        existing: [studied],
        change: ProcessedChange.replace,
        fresh: [copy('De la fuente.', a(0, 13))],
      );

      expect(plan.removed, [studied]);
      expect(contents(plan), ['De la fuente.']);
    });

    test('una oración de palabras clave con otras palabras se renueva; con '
        'las mismas, es la misma', () {
      const spans = [ProcessedSpan(start: 0, end: 4)];
      final same = part(
        'Roma cae.',
        anchor: a(0, 9),
      ).copyWith(section: ProcessedSection.keywords, spans: spans);
      final other = part(
        'Fin de algo.',
        anchor: a(10, 22),
      ).copyWith(section: ProcessedSection.keywords, spans: spans);

      final plan = planSectionChange(
        section: ProcessedSection.keywords,
        existing: [same, other],
        change: ProcessedChange.update,
        fresh: [
          ProcessedCandidate(
            content: 'Roma cae.',
            origin: ProcessedPartOrigin.copied,
            anchor: a(0, 9),
            spans: spans,
          ),
          ProcessedCandidate(
            content: 'Fin de algo.',
            origin: ProcessedPartOrigin.copied,
            anchor: a(10, 22),
            spans: const [ProcessedSpan(start: 7, end: 11)],
          ),
        ],
      );

      expect((plan.parts.first as KeptPart).part, same);
      expect(plan.removed, [other]);
      expect(plan.added, 1);
    });

    test('una copiada con una palabra elegida a mano ya es propia', () {
      final copied = part('Roma cae.', anchor: a(0, 9)).copyWith(
        section: ProcessedSection.keywords,
        spans: const [ProcessedSpan(start: 0, end: 4, chosen: true)],
      );

      expect(copied.isPristineCopy, isFalse);
      expect(copied.isVerbatim, isTrue);
      final plan = planSectionChange(
        section: ProcessedSection.keywords,
        existing: [copied],
        change: ProcessedChange.update,
      );
      expect(plan.parts.single, isA<KeptPart>());
    });
  });

  test('una parte que solo cambia de lugar también es un cambio', () {
    final plan = planSectionChange(
      section: ProcessedSection.summary,
      existing: [part('B', anchor: a(5, 6), position: 0)],
      change: ProcessedChange.add,
      fresh: [copy('A', a(0, 1))],
    );

    expect(plan.isNoOp, isFalse);
    expect(
      SectionPlan(
        section: ProcessedSection.summary,
        parts: [KeptPart(part('B', position: 1))],
        removed: const [],
      ).isNoOp,
      isFalse,
    );
    expect(
      SectionPlan(
        section: ProcessedSection.summary,
        parts: [KeptPart(part('B', position: 0))],
        removed: const [],
      ).isNoOp,
      isTrue,
    );
  });
}
