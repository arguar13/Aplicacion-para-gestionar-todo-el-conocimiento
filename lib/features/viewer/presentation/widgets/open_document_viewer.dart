import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/util/external_url_launcher.dart';
import 'package:sinapsis/features/library/presentation/screens/transcript_follow_screen.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_study_actions.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_view.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/viewer/domain/entities/resolved_viewer.dart';
import 'package:sinapsis/features/viewer/presentation/providers/viewer_providers.dart';
import 'package:sinapsis/features/viewer/presentation/screens/document_reader_screen.dart';
import 'package:sinapsis/features/viewer/presentation/screens/image_viewer_screen.dart';
import 'package:sinapsis/features/viewer/presentation/screens/media_player_screen.dart';

/// Abre el visor integrado que corresponda al archivo original de [item] a
/// pantalla completa, en vez de delegar en la app que el sistema tenga
/// asociada.
///
/// Un PDF, una página web o un libro se abren en **el mismo original que en
/// Procesado** (F45, paso 7b, mejora 16, decisión H: `OriginalScreen`): las
/// tres fichas de Resumen, Síntesis y Palabras clave arriba, que marcan sobre
/// la fuente —cada lado lo suyo, por su propia clave—, el mismo visor y el
/// mismo lector flotante. Sin su texto no hay qué marcar, y se ve solo el
/// visor.
///
/// Devuelve `false` cuando no hay ningún visor para lo que trae [item] —una
/// fuente sin archivo, un formato que no se pudo reconocer, un documento sin
/// texto extraído todavía— para que quien llama pueda caer en el "Abrir
/// con..." de siempre en vez de no hacer nada.
///
/// Qué visor le corresponde a [item] lo decide `FileViewerResolver` —el
/// mismo que usa `EmbeddedFileViewer` para mostrarlo directo en el detalle,
/// sin este viaje a una pantalla nueva—; acá solo queda mapear ese
/// resultado a la pantalla que lo muestra a pantalla completa.
Future<bool> openDocumentViewer(
  BuildContext context,
  WidgetRef ref,
  KnowledgeItem item,
) async {
  final resolved = await ref.read(fileViewerResolverProvider).resolve(item);
  if (!context.mounted) return false;

  switch (resolved) {
    case NoResolvedViewer():
      return false;

    // Una foto o un escaneo, con el texto que se leyó en ella.
    case ImageResolvedViewer(:final path):
      return _push(
        context,
        ImageViewerScreen(
          path: path,
          title: item.title,
          text: studyTextOf(item),
        ),
      );

    // Un audio o un video con su transcripción, que sigue al audio; sin
    // ella, el reproductor solo.
    case MediaResolvedViewer(:final path, :final isVideo):
      if (followedTranscriptOf(item) != null) {
        return _push(context, TranscriptFollowScreen(itemId: item.id));
      }
      return _push(
        context,
        MediaPlayerScreen(path: path, title: item.title, isVideo: isVideo),
      );

    case PdfResolvedViewer(:final path, :final text):
      return _pushOriginal(context, item, OriginalFormat.pdf, path, text);

    case WebPageResolvedViewer(:final path, :final url, :final text):
      return _pushOriginal(
        context,
        item,
        OriginalFormat.page,
        path,
        text,
        url: url,
      );

    case TextResolvedViewer(:final study?):
      return _pushOriginal(context, item, OriginalFormat.reader, null, study);

    // Un texto que no es el que se estudia —su forma principal no es la de
    // estudiar—: el lector sin nada que marcar.
    case TextResolvedViewer(:final content, :final markdown):
      return _push(
        context,
        DocumentReaderScreen(
          title: item.title,
          content: content,
          markdown: markdown,
        ),
      );

    // Un YouTube con su transcripción se lee en el marco, con «Ver en
    // YouTube» en ⋮ (F47, paso 1). Sin ella no hay qué leer: se abre el
    // video de verdad, como la vista previa embebida —ver
    // `YoutubeEmbedView`—.
    case YoutubeEmbedResolvedViewer(:final url):
      if (followedTranscriptOf(item) != null) {
        return _push(context, TranscriptFollowScreen(itemId: item.id));
      }
      return launchExternalUrl(url);
  }
}

/// El original de [item] en su visor, con sus fichas si tiene [text].
///
/// Es el mismo marco de lectura que el original de Procesado (F47, paso 1):
/// las fichas en la fila de IA marcan la fuente. De la Biblioteca nada se
/// borra: ⋮ no lleva nada en rojo.
bool _pushOriginal(
  BuildContext context,
  KnowledgeItem item,
  OriginalFormat format,
  String? path,
  StudyText? text, {
  String? url,
}) => _push(
  context,
  OriginalScreen(
    title: item.title,
    format: format,
    study: text == null ? null : OriginalStudy.source(text),
    body: OriginalView(
      format: format,
      path: path,
      url: url,
      title: item.title,
      text: text,
    ),
  ),
);

bool _push(BuildContext context, Widget screen) {
  unawaited(
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => screen)),
  );
  return true;
}
