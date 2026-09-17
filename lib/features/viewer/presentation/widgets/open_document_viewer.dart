import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/util/external_url_launcher.dart';
import 'package:sinapsis/features/viewer/domain/entities/resolved_viewer.dart';
import 'package:sinapsis/features/viewer/presentation/providers/viewer_providers.dart';
import 'package:sinapsis/features/viewer/presentation/screens/document_reader_screen.dart';
import 'package:sinapsis/features/viewer/presentation/screens/image_viewer_screen.dart';
import 'package:sinapsis/features/viewer/presentation/screens/media_player_screen.dart';
import 'package:sinapsis/features/viewer/presentation/screens/pdf_viewer_screen.dart';
import 'package:sinapsis/features/viewer/presentation/screens/web_page_viewer_screen.dart';

/// Abre el visor integrado que corresponda al archivo original de [item] a
/// pantalla completa, en vez de delegar en la app que el sistema tenga
/// asociada.
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

    case ImageResolvedViewer(:final path):
      return _push(context, ImageViewerScreen(path: path, title: item.title));

    case MediaResolvedViewer(:final path, :final isVideo):
      return _push(
        context,
        MediaPlayerScreen(path: path, title: item.title, isVideo: isVideo),
      );

    case PdfResolvedViewer(:final path):
      return _push(context, PdfViewerScreen(path: path, title: item.title));

    case WebPageResolvedViewer(:final path):
      return _push(context, WebPageViewerScreen(path: path, title: item.title));

    case TextResolvedViewer(:final content):
      return _push(
        context,
        DocumentReaderScreen(title: item.title, content: content),
      );

    // Sin pantalla propia: para YouTube, "abrir el visor a pantalla
    // completa" es exactamente lo mismo que tocar la vista previa
    // embebida — ver `YoutubeEmbedView`. Abre el video de verdad, en vez
    // de empujar una pantalla de esta app.
    case YoutubeEmbedResolvedViewer(:final url):
      return launchExternalUrl(url);
  }
}

bool _push(BuildContext context, Widget screen) {
  unawaited(
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => screen)),
  );
  return true;
}
