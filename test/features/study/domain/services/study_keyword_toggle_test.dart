import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/services/study_keyword_toggle.dart';

/// Tocar una palabra eligiendo las palabras clave (F36).
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

  KeywordToggle tap(
    DocumentStudy study,
    int offset, {
    Set<StudyMarkKind> kinds = const {StudyMarkKind.summary},
  }) => keywordToggleAt(
    content: content,
    study: study,
    sentenceKinds: kinds,
    offset: offset,
  );

  final summarized = study([
    mark('s1', StudyMarkKind.summary, first.$1, first.$2),
    keyword('k1', 'revolución'),
  ]);

  test('una palabra de una oración resaltada se agrega', () {
    final toggle = tap(summarized, content.indexOf('Inglaterra') + 3);

    expect(toggle, isA<KeywordToggleAdd>());
    final word = (toggle as KeywordToggleAdd).word;
    expect(content.substring(word.start, word.end), 'Inglaterra');
  });

  test('tocar justo detrás de la última letra también es esa palabra', () {
    final end = content.indexOf('Inglaterra') + 'Inglaterra'.length;

    final toggle = tap(summarized, end);

    final word = (toggle as KeywordToggleAdd).word;
    expect(content.substring(word.start, word.end), 'Inglaterra');
  });

  test('una que ya es clave se saca', () {
    final toggle = tap(summarized, content.indexOf('revolución') + 1);

    expect(toggle, isA<KeywordToggleRemove>());
    expect((toggle as KeywordToggleRemove).markId, 'k1');
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

    expect(tap(full, content.indexOf('Inglaterra')), isA<KeywordToggleFull>());
    expect(tap(full, content.indexOf('vapor')), isA<KeywordToggleRemove>());
  });

  test('la última palabra de una oración sin punto final también se toca '
      'desde detrás de su última letra', () {
    final open = study([
      mark('s2', StudyMarkKind.summary, second.$1, second.$2 - 1),
    ]);

    final toggle = tap(open, second.$2 - 1);

    final word = (toggle as KeywordToggleAdd).word;
    expect(content.substring(word.start, word.end), 'rápido');
  });

  test('las palabras clave de otra oración no cuentan para el tope', () {
    final busy = study([
      mark('s1', StudyMarkKind.summary, first.$1, first.$2),
      keyword('k1', 'revolución'),
      keyword('k2', 'industrial'),
      keyword('k3', 'vapor'),
      keyword('k4', 'fábricas'),
    ]);

    expect(tap(busy, content.indexOf('carbón')), isA<KeywordToggleAdd>());
  });

  test('fuera de una oración resaltada, entre palabras o en una que no dice '
      'nada sola, no pasa nada', () {
    expect(
      tap(summarized, content.indexOf('fábricas')),
      isA<KeywordToggleNone>(),
    );
    expect(
      tap(summarized, content.indexOf(' y ') + 1),
      isA<KeywordToggleNone>(),
    );
    expect(
      tap(summarized, content.indexOf(' en ') + 1),
      isA<KeywordToggleNone>(),
    );
    expect(
      tap(summarized, content.indexOf('. Las') + 1),
      isA<KeywordToggleNone>(),
    );
  });

  test('cuentan las oraciones de lo que se ve: la síntesis no es el '
      'resumen', () {
    final both = study([
      mark('s1', StudyMarkKind.summary, first.$1, first.$2),
      mark('y2', StudyMarkKind.synthesis, second.$1, second.$2),
    ]);
    final fabricas = content.indexOf('fábricas');

    expect(tap(both, fabricas), isA<KeywordToggleNone>());
    expect(
      tap(both, fabricas, kinds: {StudyMarkKind.synthesis}),
      isA<KeywordToggleAdd>(),
    );
    expect(
      tap(
        both,
        content.indexOf('vapor'),
        kinds: {StudyMarkKind.summary, StudyMarkKind.synthesis},
      ),
      isA<KeywordToggleAdd>(),
    );
  });
}
