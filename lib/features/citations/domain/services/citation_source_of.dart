import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';

/// Lo que un estilo necesita para citar [item] (F15): su título, sus datos
/// bibliográficos —[reference]—, la fecha con la exactitud con que se sabe y de
/// dónde salió.
///
/// La fecha junta lo que se guarda en dos lugares: la de publicación de la
/// fuente y la exactitud, que es de la referencia.
CitationSource citationSourceOf(KnowledgeItem item, ReferenceData reference) =>
    CitationSource(
      title: item.title,
      reference: reference,
      date: PublicationDate.fromStored(
        item.source.publishedAt,
        reference.publicationPrecision,
      ),
      url: item.source.url,
      authorName: item.source.authorName,
      capturedAt: item.source.capturedAt,
      kind: item.source.kind,
    );
