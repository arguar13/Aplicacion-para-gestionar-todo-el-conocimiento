import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';

/// Con qué nombre conoce el lector en voz alta a la parte [partId] de un
/// documento procesado: el `sourceKey` de sus pedazos, con las posiciones de
/// su texto tal cual se guarda. Lo usa quien la muestra (`ReadAloudText`) para
/// resaltar lo que suena.
String processedPartReadKey(String partId) => 'processed-part:$partId';

/// Lo que el lector en voz alta lee de un documento procesado (F41) y, en
/// orden, qué parte es cada página del texto: con eso la pantalla dice por
/// dónde empezar —la página que se está mirando—.
typedef ProcessedReadable = ({
  ReadableDocument document,
  List<String> textPageIds,
});

/// Qué parte de lo procesado se lee con cada capa de lo estudiado (F39). Las
/// notas y los fragmentos no tienen capa propia: se leen con «Todo».
const _scopeOf = <ProcessedSection, ReadScope>{
  ProcessedSection.summary: ReadScope.summary,
  ProcessedSection.synthesis: ReadScope.synthesis,
};

/// Un documento procesado para leer en voz alta (F41), como el detalle de un
/// elemento: «Todo» lee sus secciones de punta a punta, en el orden en que se
/// ven, y el resumen y la síntesis se leen también solos.
///
/// Se arma fuera de la pantalla, como el de un libro en el detalle
/// (`readableTextProvider`): las partes se piden a la base —que corre en su
/// propio hilo— y, si son largas, se parten en otro (`compute`). Mientras
/// tanto es `null`, y el botón flotante aparece cuando está listo. Se vuelve a
/// armar cuando el documento cambia —se edita o se quita una parte—, no
/// cuando se pasa de página.
final processedReadableProvider = FutureProvider.autoDispose
    .family<ProcessedReadable?, String>((ref, documentId) async {
      final document = await ref.watch(
        processedDocumentProvider(documentId).future,
      );
      if (document == null) return null;
      final parts = await ref
          .read(processedRepositoryProvider)
          .partsOf(documentId);
      final list = parts.getRight().toNullable();
      if (list == null || list.isEmpty) return null;

      final kind = document.summary.sourceKind;
      final job = (
        parts: [
          for (final part in list)
            (
              section: part.section,
              part: (
                sourceKey: processedPartReadKey(part.id),
                text: part.content,
                // El texto se muestra tal cual se guardó; lo que no se
                // pronuncia —los símbolos de formato de una página, la marca
                // «[3:15]» de una transcripción— se saca solo de lo que suena.
                markdown: kind == SourceKind.webPage,
                transcript: _transcripts.contains(kind),
              ),
            ),
        ],
      );
      final characters = list.fold(0, (sum, p) => sum + p.content.length);
      final segmented = characters <= kSegmentsInlineChars
          ? _segment(job)
          : await compute(_segment, job);

      return (
        document: ReadableDocument(
          id: 'processed:$documentId',
          title: document.title,
          segments: segmented.all,
          scopes: segmented.scopes,
        ),
        textPageIds: [
          for (final part in list)
            if (part.section == ProcessedSection.text) part.id,
        ],
      );
    });

const _transcripts = {SourceKind.youtube, SourceKind.audio, SourceKind.video};

typedef _SegmentJob = ({
  List<({ProcessedSection section, ReadablePart part})> parts,
});

typedef _Segmented = ({
  List<ReadableSegment> all,
  Map<ReadScope, List<ReadableSegment>> scopes,
});

/// Parte cada parte en lo que se lee de una vez, cada una con su propio
/// `sourceKey`: lo que suena se resalta en su parte, en su lugar.
_Segmented _segment(_SegmentJob job) {
  final all = <ReadableSegment>[];
  final scopes = <ReadScope, List<ReadableSegment>>{};
  for (final (:section, :part) in job.parts) {
    final segments = buildReadableSegments(
      part.text,
      sourceKey: part.sourceKey,
      markdown: part.markdown,
      transcript: part.transcript,
    );
    all.addAll(segments);
    if (_scopeOf[section] case final scope?) {
      (scopes[scope] ??= []).addAll(segments);
    }
  }
  return (all: all, scopes: scopes);
}

/// La parte que es la página [page] del texto, para empezar a leer ahí; `null`
/// si no hay texto o la página no existe.
String? textPageIdAt(ProcessedReadable readable, int page) =>
    page >= 0 && page < readable.textPageIds.length
    ? readable.textPageIds[page]
    : null;
