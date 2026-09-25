import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/chat_source.dart';
import 'package:sinapsis/features/notes/domain/services/derived_claim_anchor.dart';
import 'package:sinapsis/features/notes/domain/services/derived_note_response_parser.dart';

/// Una fuente con su offset absoluto de arranque, para armar `ChatSource` de
/// prueba —el mismo criterio que `LibraryVaultRetriever` produce de verdad
/// (F16, D2)—.
ChatSource _source({
  required String itemId,
  required String excerpt,
  int sourceCharStart = 100,
}) {
  return ChatSource(
    itemId: itemId,
    itemTitle: 'Título de $itemId',
    excerpt: excerpt,
    sourceCharStart: sourceCharStart,
    sourceCharEnd: sourceCharStart + excerpt.length,
  );
}

void main() {
  test('una cita textual ancla, con el offset corrido al del texto real', () {
    final source = _source(
      itemId: 'a',
      excerpt: 'Rómulo fundó la ciudad en el 753 a. C.',
    );
    final raw = [
      const RawDerivedSection(
        claims: [
          RawDerivedClaim(
            text: 'Roma fue fundada por Rómulo',
            quote: 'Rómulo fundó la ciudad',
          ),
        ],
      ),
    ];

    final sections = anchorDerivedClaims(raw, [source]);

    expect(sections, hasLength(1));
    final claim = sections.single.claims.single;
    expect(claim.text, 'Roma fue fundada por Rómulo');
    expect(claim.sourceItemId, 'a');
    final relative = source.excerpt.indexOf('Rómulo fundó la ciudad');
    expect(claim.sourceCharStart, 100 + relative);
    expect(
      claim.sourceCharEnd,
      100 + relative + 'Rómulo fundó la ciudad'.length,
    );
  });

  test('una cita que no aparece textual descarta la afirmación entera', () {
    final source = _source(itemId: 'a', excerpt: 'texto real de la fuente');
    final raw = [
      const RawDerivedSection(
        claims: [
          RawDerivedClaim(text: 'una afirmación', quote: 'algo que no está'),
        ],
      ),
    ];

    expect(anchorDerivedClaims(raw, [source]), isEmpty);
  });

  test('una afirmación sin cita nunca ancla', () {
    final source = _source(itemId: 'a', excerpt: 'texto real de la fuente');
    final raw = [
      const RawDerivedSection(
        claims: [RawDerivedClaim(text: 'una afirmación sin cita')],
      ),
    ];

    expect(anchorDerivedClaims(raw, [source]), isEmpty);
  });

  test('una fuente sin sourceCharStart nunca ancla nada', () {
    const source = ChatSource(
      itemId: 'a',
      itemTitle: 'Nota manual',
      excerpt: 'texto de una nota sin chunks',
    );
    final raw = [
      const RawDerivedSection(
        claims: [
          RawDerivedClaim(text: 'una afirmación', quote: 'texto de una nota'),
        ],
      ),
    ];

    expect(anchorDerivedClaims(raw, [source]), isEmpty);
  });

  test(
    'una sección se descarta entera si ninguna de sus afirmaciones ancla',
    () {
      final source = _source(itemId: 'a', excerpt: 'texto real');
      final raw = [
        const RawDerivedSection(
          heading: 'título',
          claims: [
            RawDerivedClaim(text: 'sin cita'),
            RawDerivedClaim(text: 'con cita falsa', quote: 'no está'),
          ],
        ),
      ];

      expect(anchorDerivedClaims(raw, [source]), isEmpty);
    },
  );

  test(
    'una sección con al menos una afirmación anclada sobrevive con esa sola',
    () {
      final source = _source(itemId: 'a', excerpt: 'texto real de la fuente');
      final raw = [
        const RawDerivedSection(
          heading: 'título',
          claims: [
            RawDerivedClaim(text: 'sin cita'),
            RawDerivedClaim(text: 'con cita real', quote: 'texto real'),
          ],
        ),
      ];

      final sections = anchorDerivedClaims(raw, [source]);

      expect(sections.single.heading, 'título');
      expect(sections.single.claims, hasLength(1));
      expect(sections.single.claims.single.text, 'con cita real');
    },
  );

  test('cada fuente ancla como mucho una afirmación: la segunda que la citaría '
      'se descarta, no se guarda sin ancla ni pisa la primera', () {
    final source = _source(
      itemId: 'a',
      excerpt: 'primera frase. segunda frase.',
    );
    final raw = [
      const RawDerivedSection(
        claims: [
          RawDerivedClaim(text: 'afirmación uno', quote: 'primera frase'),
          RawDerivedClaim(text: 'afirmación dos', quote: 'segunda frase'),
        ],
      ),
    ];

    final sections = anchorDerivedClaims(raw, [source]);

    expect(sections.single.claims, hasLength(1));
    expect(sections.single.claims.single.text, 'afirmación uno');
  });

  test('dos afirmaciones distintas anclan cada una a su propia fuente', () {
    final sourceA = _source(
      itemId: 'a',
      excerpt: 'texto de la fuente a',
      sourceCharStart: 0,
    );
    final sourceB = _source(
      itemId: 'b',
      excerpt: 'texto de la fuente b',
      sourceCharStart: 500,
    );
    final raw = [
      const RawDerivedSection(
        claims: [
          RawDerivedClaim(text: 'de a', quote: 'fuente a'),
          RawDerivedClaim(text: 'de b', quote: 'fuente b'),
        ],
      ),
    ];

    final sections = anchorDerivedClaims(raw, [sourceA, sourceB]);

    expect(sections.single.claims, hasLength(2));
    expect(sections.single.claims[0].sourceItemId, 'a');
    expect(sections.single.claims[1].sourceItemId, 'b');
  });

  test('sin fuentes, nada ancla', () {
    final raw = [
      const RawDerivedSection(
        claims: [RawDerivedClaim(text: 'algo', quote: 'lo que sea')],
      ),
    ];

    expect(anchorDerivedClaims(raw, []), isEmpty);
  });

  test('sin secciones crudas, no hay secciones ancladas', () {
    expect(anchorDerivedClaims([], []), isEmpty);
  });
}
