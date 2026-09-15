import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_style.dart';
import 'package:sinapsis/features/citations/domain/services/citation_formatter.dart';

void main() {
  KnowledgeItem buildItem({
    String title = 'La estructura de las revoluciones científicas',
    String? authorName,
    String? url,
    DateTime? publishedAt,
  }) {
    return KnowledgeItem(
      id: 'item-1',
      title: title,
      source: Source(
        id: 'source-1',
        kind: SourceKind.webPage,
        capturedAt: DateTime(2026, 9, 14),
        authorName: authorName,
        url: url,
        publishedAt: publishedAt,
      ),
      processingState: ProcessingState.ready,
      createdAt: DateTime(2026, 9, 14),
      updatedAt: DateTime(2026, 9, 14),
    );
  }

  group('APA', () {
    test('con autor, año y sitio, arma la cita completa', () {
      final item = buildItem(
        authorName: 'Thomas Kuhn',
        url: 'https://www.ejemplo.org/articulo',
        publishedAt: DateTime(1962),
      );

      final citation = formatCitation(item, CitationStyle.apa);

      expect(
        citation,
        'Thomas Kuhn. (1962). La estructura de las revoluciones '
        'científicas. ejemplo.org. https://www.ejemplo.org/articulo',
      );
    });

    test('sin autor, empieza directo por el título', () {
      final item = buildItem(url: 'https://ejemplo.org/nota');

      final citation = formatCitation(item, CitationStyle.apa);

      expect(citation, startsWith('(s.f.)'));
      expect(citation, isNot(contains('null')));
    });

    test('sin fecha de publicación, usa "s.f." en vez de inventar una', () {
      final item = buildItem(authorName: 'Autora');

      final citation = formatCitation(item, CitationStyle.apa);

      expect(citation, contains('(s.f.)'));
      // La fecha de captura (2026) no se usa como si fuera de publicación.
      expect(citation, isNot(contains('2026')));
    });
  });

  group('MLA', () {
    test('el título va entre comillas, y el autor primero', () {
      final item = buildItem(
        authorName: 'Thomas Kuhn',
        url: 'https://ejemplo.org/articulo',
        publishedAt: DateTime(1962),
      );

      final citation = formatCitation(item, CitationStyle.mla);

      expect(
        citation,
        'Thomas Kuhn. "La estructura de las revoluciones científicas." '
        'ejemplo.org, 1962, https://ejemplo.org/articulo',
      );
    });
  });

  group('Chicago', () {
    test('el año va justo después del autor', () {
      final item = buildItem(
        authorName: 'Thomas Kuhn',
        url: 'https://ejemplo.org/articulo',
        publishedAt: DateTime(1962),
      );

      final citation = formatCitation(item, CitationStyle.chicago);

      expect(
        citation,
        'Thomas Kuhn. 1962. "La estructura de las revoluciones '
        'científicas." ejemplo.org. https://ejemplo.org/articulo',
      );
    });
  });

  group('sin enlace', () {
    test('ninguno de los tres estilos menciona un sitio ni una URL', () {
      final item = buildItem(authorName: 'Yo mismo');

      for (final style in CitationStyle.values) {
        final citation = formatCitation(item, style);
        expect(citation, isNot(contains('http')));
        expect(citation, isNot(contains('null')));
      }
    });
  });
}
