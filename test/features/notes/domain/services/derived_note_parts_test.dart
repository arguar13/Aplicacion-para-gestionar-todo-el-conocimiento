import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/chat_source.dart';
import 'package:sinapsis/features/notes/domain/services/derived_note_generator.dart';
import 'package:sinapsis/features/notes/domain/services/derived_note_parts.dart';

/// Repartir las fuentes de un derivado en partes que entran en la ventana, y
/// juntar lo que dio cada una (F30).
void main() {
  ChatSource source(String id, int chars, {int start = 0}) => ChatSource(
    itemId: id,
    itemTitle: 'Fuente $id',
    excerpt: List.filled(chars ~/ 5, 'roma ').join(),
    sourceCharStart: start,
    sourceCharEnd: start + chars,
  );

  group('packDerivedSources', () {
    test('en orden, sin pasarse de los caracteres de una parte', () {
      final sources = [for (var i = 0; i < 10; i++) source('$i', 400)];

      final parts = packDerivedSources(sources, partChars: 1000, maxParts: 9);

      expect(parts.expand((p) => p).map((s) => s.itemId), [
        for (var i = 0; i < 10; i++) '$i',
      ]);
      for (final part in parts) {
        expect(
          part.map(derivedSourceChars).fold(0, (a, b) => a + b),
          lessThanOrEqualTo(1000),
        );
      }
    });

    test('como mucho el tope de partes: lo que no entra, las últimas, queda '
        'afuera', () {
      final sources = [for (var i = 0; i < 10; i++) source('$i', 400)];

      final parts = packDerivedSources(sources, partChars: 1000, maxParts: 2);

      expect(parts, hasLength(2));
      expect(parts.expand((p) => p).map((s) => s.itemId), ['0', '1', '2', '3']);
    });

    test('una fuente más larga que una parte va sola en la suya', () {
      final parts = packDerivedSources([
        source('a', 100),
        source('larga', 5000),
        source('b', 100),
      ], partChars: 1000);

      expect(parts.map((p) => p.map((s) => s.itemId).toList()), [
        ['a'],
        ['larga'],
        ['b'],
      ]);
    });

    test('sin fuentes, sin partes', () {
      expect(packDerivedSources(const []), isEmpty);
    });
  });

  group('mergeDerivedSections', () {
    DerivedClaim claim(String itemId) => DerivedClaim(
      text: 'de $itemId',
      sourceItemId: itemId,
      sourceCharStart: 0,
      sourceCharEnd: 4,
    );

    test('junta las secciones del mismo título, en el orden en que '
        'aparecieron, y las sin título en una sola', () {
      final merged = mergeDerivedSections([
        [
          DerivedSection(heading: 'Roma', claims: [claim('a')]),
          DerivedSection(claims: [claim('b')]),
        ],
        [
          DerivedSection(heading: 'Grecia', claims: [claim('c')]),
          DerivedSection(heading: ' roma ', claims: [claim('d')]),
          DerivedSection(claims: [claim('e')]),
        ],
      ]);

      expect(merged.map((s) => s.heading), ['Roma', null, 'Grecia']);
      expect(merged.map((s) => s.claims.map((c) => c.sourceItemId).toList()), [
        ['a', 'd'],
        ['b', 'e'],
        ['c'],
      ]);
    });

    test('una fuente cita una sola afirmación: la segunda se descarta, y una '
        'sección que queda vacía también', () {
      final merged = mergeDerivedSections([
        [
          DerivedSection(heading: 'Roma', claims: [claim('a')]),
        ],
        [
          DerivedSection(heading: 'Grecia', claims: [claim('a')]),
        ],
      ]);

      expect(merged, hasLength(1));
      expect(merged.single.heading, 'Roma');
    });
  });

  group('fitSourcesToWindow', () {
    /// Cuatro caracteres por token, como en las pruebas del modelo.
    Future<int> count(String text) async => (text.length / 4).ceil();
    String build(List<ChatSource> sources) =>
        sources.map((s) => '${s.itemTitle}\n${s.excerpt}').join('\n\n');

    test('lo que ya entra no se toca', () async {
      final sources = [source('a', 400), source('b', 400)];

      final fitted = await fitSourcesToWindow(
        sources,
        roomTokens: 1000,
        countTokens: count,
        build: build,
      );

      expect(fitted, sources);
    });

    test('acorta los fragmentos por el final, en el borde de una palabra, '
        'con su fin corrido a la par', () async {
      final sources = [
        source('a', 2000, start: 100),
        source('b', 2000, start: 50),
      ];

      final fitted = await fitSourcesToWindow(
        sources,
        roomTokens: 500,
        countTokens: count,
        build: build,
      );

      expect(await count(build(fitted)), lessThanOrEqualTo(500));
      expect(fitted.map((s) => s.itemId), ['a', 'b']);
      for (final (i, s) in fitted.indexed) {
        expect(s.excerpt, endsWith('roma…'));
        final kept = s.excerpt.length - 1;
        expect(s.sourceCharStart, sources[i].sourceCharStart);
        expect(s.sourceCharEnd, s.sourceCharStart! + kept);
        expect(sources[i].excerpt, startsWith(s.excerpt.substring(0, kept)));
      }
    });

    test('si para entrar un fragmento quedaría muy corto, saca la última '
        'fuente', () async {
      final sources = [for (var i = 0; i < 6; i++) source('$i', 400)];

      final fitted = await fitSourcesToWindow(
        sources,
        roomTokens: 150,
        countTokens: count,
        build: build,
      );

      expect(fitted.length, lessThan(sources.length));
      expect(fitted.map((s) => s.itemId), [
        for (var i = 0; i < fitted.length; i++) '$i',
      ]);
      expect(await count(build(fitted)), lessThanOrEqualTo(150));
    });

    test('si ni una entra, vacío', () async {
      final fitted = await fitSourcesToWindow(
        [source('a', 400)],
        roomTokens: 5,
        countTokens: count,
        build: build,
      );

      expect(fitted, isEmpty);
    });
  });
}
