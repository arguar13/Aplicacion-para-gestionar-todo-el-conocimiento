import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/organize/domain/repositories/organize_repository.dart';
import 'package:sinapsis/features/viewer/domain/services/document_highlighter.dart';

class _MockOrganizeRepository extends Mock implements OrganizeRepository {}

void main() {
  late _MockOrganizeRepository repository;
  const content = 'Hola mundo cruel---Segunda pagina';

  setUpAll(() => registerFallbackValue(HighlightStyle.fill));

  setUp(() => repository = _MockOrganizeRepository());

  void stub({int failAt = -1}) {
    var calls = 0;
    when(
      () => repository.createHighlight(
        renditionId: any(named: 'renditionId'),
        startOffset: any(named: 'startOffset'),
        endOffset: any(named: 'endOffset'),
        excerpt: any(named: 'excerpt'),
        note: any(named: 'note'),
        color: any(named: 'color'),
        style: any(named: 'style'),
      ),
    ).thenAnswer((invocation) async {
      final call = calls++;
      if (call == failAt) return const Left(Failure.cache(message: 'no'));
      return Right(
        Highlight(
          id: 'h$call',
          renditionId: 'r1',
          startOffset: invocation.namedArguments[#startOffset] as int,
          endOffset: invocation.namedArguments[#endOffset] as int,
          excerpt: invocation.namedArguments[#excerpt] as String,
          createdAt: DateTime(2026),
        ),
      );
    });
  }

  test('guarda un resaltado por tramo, con su texto copiado, el color y el '
      'estilo', () async {
    stub();

    final outcome = await saveHighlights(
      repository,
      renditionId: 'r1',
      content: content,
      slices: const [(start: 5, end: 10), (start: 19, end: 26)],
      color: HighlightColor.violet,
      style: HighlightStyle.underline,
      note: 'ojo',
    );

    expect(outcome.created, isTrue);
    expect(outcome.highlights.map((h) => h.excerpt), ['mundo', 'Segunda']);
    verify(
      () => repository.createHighlight(
        renditionId: 'r1',
        startOffset: 5,
        endOffset: 10,
        excerpt: 'mundo',
        note: 'ojo',
        color: HighlightColor.violet,
        style: HighlightStyle.underline,
      ),
    ).called(1);
    // La nota queda en el primero.
    verify(
      () => repository.createHighlight(
        renditionId: 'r1',
        startOffset: 19,
        endOffset: 26,
        excerpt: 'Segunda',
        color: HighlightColor.violet,
        style: HighlightStyle.underline,
      ),
    ).called(1);
  });

  test('sin color ni estilo: el de siempre y de fondo', () async {
    stub();

    await saveHighlights(
      repository,
      renditionId: 'r1',
      content: content,
      slices: const [(start: 0, end: 4)],
    );

    verify(
      () => repository.createHighlight(
        renditionId: 'r1',
        startOffset: 0,
        endOffset: 4,
        excerpt: 'Hola',
      ),
    ).called(1);
  });

  test('sin tramos no hay qué guardar', () async {
    final outcome = await saveHighlights(
      repository,
      renditionId: 'r1',
      content: content,
      slices: const [],
    );

    expect(outcome.created, isFalse);
    expect(outcome.issue, HighlightIssue.nothingSelected);
    verifyNever(
      () => repository.createHighlight(
        renditionId: any(named: 'renditionId'),
        startOffset: any(named: 'startOffset'),
        endOffset: any(named: 'endOffset'),
        excerpt: any(named: 'excerpt'),
      ),
    );
  });

  test('si uno no se guarda, se corta y se avisa; los ya guardados quedan en '
      'el resultado', () async {
    stub(failAt: 1);

    final outcome = await saveHighlights(
      repository,
      renditionId: 'r1',
      content: content,
      slices: const [
        (start: 0, end: 4),
        (start: 5, end: 10),
        (start: 19, end: 26),
      ],
    );

    expect(outcome.issue, HighlightIssue.notSaved);
    expect(outcome.failure, isA<CacheFailure>());
    expect(outcome.highlights.map((h) => h.id), ['h0']);
    verify(
      () => repository.createHighlight(
        renditionId: any(named: 'renditionId'),
        startOffset: any(named: 'startOffset'),
        endOffset: any(named: 'endOffset'),
        excerpt: any(named: 'excerpt'),
        note: any(named: 'note'),
        color: any(named: 'color'),
        style: any(named: 'style'),
      ),
    ).called(2);
  });

  test('la ubicación sabe si se encontró', () {
    const found = SelectionLocation.found([(start: 0, end: 1)]);
    const failed = SelectionLocation.failed(HighlightIssue.scanned);

    expect(found.found, isTrue);
    expect(failed.found, isFalse);
    expect(failed.slices, isEmpty);
  });
}
