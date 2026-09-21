import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/citations/domain/services/citation_source_of.dart';

/// De un elemento de la biblioteca a lo que un estilo necesita para citarlo
/// (F15).
void main() {
  KnowledgeItem item({
    DateTime? publishedAt,
    String? url = 'https://sitio.org/a',
    String? authorName = 'Ana Pérez',
    SourceKind kind = SourceKind.webPage,
  }) => KnowledgeItem(
    id: 'a',
    title: 'Una página',
    source: Source(
      id: 'src-a',
      kind: kind,
      capturedAt: DateTime(2026, 9, 11, 10),
      url: url,
      authorName: authorName,
      publishedAt: publishedAt,
    ),
    processingState: ProcessingState.ready,
    createdAt: DateTime(2026, 9, 11, 10),
    updatedAt: DateTime(2026, 9, 11, 10),
  );

  test(
    'lleva el título, el enlace, el autor, la captura y el tipo de captura',
    () {
      final source = citationSourceOf(item(), const ReferenceData());

      expect(source.title, 'Una página');
      expect(source.url, 'https://sitio.org/a');
      expect(source.authorName, 'Ana Pérez');
      expect(source.capturedAt, DateTime(2026, 9, 11, 10));
      expect(source.kind, SourceKind.webPage);
    },
  );

  test('los datos bibliográficos van tal cual', () {
    const reference = ReferenceData(
      type: ReferenceType.article,
      publisher: 'Editorial',
    );

    final source = citationSourceOf(item(), reference);

    expect(source.reference, same(reference));
    expect(source.type, ReferenceType.article);
  });

  test('la fecha junta la de la fuente con la exactitud de la referencia', () {
    final published = DateTime(2020, 3, 15);

    expect(
      citationSourceOf(
        item(publishedAt: published),
        const ReferenceData(),
      ).date,
      PublicationDate.ofDay(2020, 3, 15),
    );
    expect(
      citationSourceOf(
        item(publishedAt: published),
        const ReferenceData(publicationPrecision: PublicationPrecision.year),
      ).date,
      PublicationDate.ofYear(2020),
    );
    expect(
      citationSourceOf(
        item(publishedAt: published),
        const ReferenceData(publicationPrecision: PublicationPrecision.undated),
      ).date,
      const PublicationDate.undated(),
    );
  });

  test('sin fecha guardada, la fecha es desconocida', () {
    final source = citationSourceOf(item(), const ReferenceData());

    expect(source.date.isUnknown, isTrue);
  });
}
