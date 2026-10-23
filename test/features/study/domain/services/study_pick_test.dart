import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/services/study_pick.dart';

/// Tocar el texto eligiendo a mano el resumen, la síntesis o las palabras
/// clave (F36, F39).
void main() {
  const content =
      'La revolución industrial empezó en Inglaterra con vapor y carbón. '
      'Las fábricas crecieron rápido.';
  final first = (0, content.indexOf(' Las'));
  final second = (content.indexOf('Las'), content.length);

  StudyMark mark(
    String id,
    StudyMarkKind kind,
    int start,
    int end, {
    ContentOrigin origin = ContentOrigin.ai,
  }) => StudyMark(id: id, kind: kind, origin: origin, start: start, end: end);

  StudyMark keyword(String id, String word) {
    final start = content.indexOf(word);
    return mark(id, StudyMarkKind.keyword, start, start + word.length);
  }

  DocumentStudy study(List<StudyMark> marks) => DocumentStudy(
    marks: marks,
    analyzedUntil: content.length,
    complete: true,
  );

  StudyPickToggle tap(
    DocumentStudy study,
    int offset, {
    StudyMarkKind kind = StudyMarkKind.keyword,
  }) => studyPickAt(
    content: content,
    markdown: false,
    study: study,
    kind: kind,
    offset: offset,
  );

  String picked(StudyPickToggle toggle) {
    final add = toggle as StudyPickAdd;
    return content.substring(add.start, add.end);
  }

  final summarized = study([
    mark('s1', StudyMarkKind.summary, first.$1, first.$2),
    keyword('k1', 'revolución'),
  ]);

  group('el resumen y la síntesis', () {
    test('tocar una oración la pone, entera, con lo que se elige', () {
      final toggle = tap(
        DocumentStudy.notStarted,
        content.indexOf('crecieron'),
        kind: StudyMarkKind.summary,
      );

      expect(toggle, isA<StudyPickAdd>());
      expect((toggle as StudyPickAdd).kind, StudyMarkKind.summary);
      expect(picked(toggle), 'Las fábricas crecieron rápido.');
    });

    test('tocar una que ya está la saca, la haya puesto la IA o la persona, '
        'también justo detrás de su última letra', () {
      expect(
        tap(summarized, content.indexOf('vapor'), kind: StudyMarkKind.summary),
        const StudyPickRemove('s1'),
      );
      expect(
        tap(summarized, first.$2, kind: StudyMarkKind.summary),
        const StudyPickRemove('s1'),
      );

      final mine = study([
        mark(
          'u1',
          StudyMarkKind.synthesis,
          second.$1,
          second.$2,
          origin: ContentOrigin.user,
        ),
      ]);
      expect(
        tap(mine, second.$1 + 2, kind: StudyMarkKind.synthesis),
        const StudyPickRemove('u1'),
      );
    });

    test('lo del resumen no cuenta para la síntesis', () {
      final toggle = tap(
        summarized,
        content.indexOf('vapor'),
        kind: StudyMarkKind.synthesis,
      );

      expect((toggle as StudyPickAdd).kind, StudyMarkKind.synthesis);
      expect(toggle.start, first.$1);
    });

    test('una marca de un análisis de antes, partida un poco distinto, '
        'también sale', () {
      final older = study([
        mark('s1', StudyMarkKind.summary, first.$1 + 3, first.$2 - 1),
      ]);

      expect(
        tap(older, content.indexOf('La'), kind: StudyMarkKind.summary),
        const StudyPickRemove('s1'),
      );
    });

    test('entre dos oraciones no hay qué elegir', () {
      const spaced = 'Uno dos.     Tres cuatro.';
      expect(
        studyPickAt(
          content: spaced,
          markdown: false,
          study: DocumentStudy.notStarted,
          kind: StudyMarkKind.summary,
          offset: spaced.indexOf('Tres') - 2,
        ),
        isA<StudyPickNone>(),
      );
    });
  });

  group('las palabras clave', () {
    test('una palabra de una oración resaltada se agrega', () {
      final toggle = tap(summarized, content.indexOf('Inglaterra') + 3);

      expect((toggle as StudyPickAdd).kind, StudyMarkKind.keyword);
      expect(picked(toggle), 'Inglaterra');
    });

    test('y también una de cualquier oración, sin resumen (F39)', () {
      expect(
        picked(tap(DocumentStudy.notStarted, content.indexOf('fábricas'))),
        'fábricas',
      );
      expect(picked(tap(summarized, content.indexOf('fábricas'))), 'fábricas');
    });

    test('tocar justo detrás de la última letra también es esa palabra', () {
      final end = content.indexOf('Inglaterra') + 'Inglaterra'.length;

      expect(picked(tap(summarized, end)), 'Inglaterra');
    });

    test('la última palabra de una oración también se toca desde detrás de '
        'su última letra', () {
      final end = content.indexOf('rápido') + 'rápido'.length;

      expect(picked(tap(DocumentStudy.notStarted, end)), 'rápido');
    });

    test('una que ya es clave se saca', () {
      expect(
        tap(summarized, content.indexOf('revolución') + 1),
        const StudyPickRemove('k1'),
      );
    });

    test('con cuatro en la oración, avisa en vez de agregar una quinta, pero '
        'sacar sigue andando', () {
      final full = study([
        mark('s1', StudyMarkKind.summary, first.$1, first.$2),
        keyword('k1', 'revolución'),
        keyword('k2', 'industrial'),
        keyword('k3', 'vapor'),
        keyword('k4', 'carbón'),
        // De otra oración: no cuenta para esta.
        keyword('k5', 'fábricas'),
      ]);

      expect(tap(full, content.indexOf('Inglaterra')), isA<StudyPickFull>());
      expect(tap(full, content.indexOf('vapor')), const StudyPickRemove('k3'));
    });

    test('el tope es por oración, aunque la oración no esté resaltada', () {
      final busy = study([
        keyword('k1', 'revolución'),
        keyword('k2', 'industrial'),
        keyword('k3', 'vapor'),
        keyword('k4', 'carbón'),
      ]);

      expect(tap(busy, content.indexOf('Inglaterra')), isA<StudyPickFull>());
      expect(tap(busy, content.indexOf('fábricas')), isA<StudyPickAdd>());
    });

    test('en una palabra que no dice nada sola, no pasa nada', () {
      expect(tap(summarized, content.indexOf(' y ') + 1), isA<StudyPickNone>());
      expect(
        tap(summarized, content.indexOf(' en ') + 1),
        isA<StudyPickNone>(),
      );
      expect(tap(summarized, second.$1), isA<StudyPickNone>());
    });
  });

  test('otro texto se parte de nuevo: no queda pegado al anterior', () {
    const other = 'Uno dos. Tres cuatro.';
    final toggle = studyPickAt(
      content: other,
      markdown: false,
      study: DocumentStudy.notStarted,
      kind: StudyMarkKind.summary,
      offset: other.indexOf('cuatro'),
    );
    final add = toggle as StudyPickAdd;

    expect(other.substring(add.start, add.end), 'Tres cuatro.');
    expect(
      picked(
        tap(
          DocumentStudy.notStarted,
          content.indexOf('vapor'),
          kind: StudyMarkKind.summary,
        ),
      ),
      content.substring(first.$1, first.$2),
    );
  });
}
