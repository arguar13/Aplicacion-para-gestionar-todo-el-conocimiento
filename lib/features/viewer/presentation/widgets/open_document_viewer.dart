import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/features/viewer/presentation/screens/document_reader_screen.dart';
import 'package:sinapsis/features/viewer/presentation/screens/image_viewer_screen.dart';
import 'package:sinapsis/features/viewer/presentation/screens/media_player_screen.dart';
import 'package:sinapsis/features/viewer/presentation/screens/pdf_viewer_screen.dart';
import 'package:sinapsis/features/viewer/presentation/screens/web_page_viewer_screen.dart';

/// Abre el visor integrado que corresponda al archivo original de [item],
/// en vez de delegar en la app que el sistema tenga asociada.
///
/// Devuelve `false` cuando no hay ningún visor para lo que trae [item] —una
/// fuente sin archivo, un formato que no se pudo reconocer, un documento sin
/// texto extraído todavía— para que quien llama pueda caer en el "Abrir
/// con..." de siempre en vez de no hacer nada.
Future<bool> openDocumentViewer(
  BuildContext context,
  WidgetRef ref,
  KnowledgeItem item,
) async {
  final relativePath = item.source.originalFilePath;
  if (relativePath == null) return false;

  final path = await ref.read(fileStoreProvider).resolve(relativePath);
  if (!context.mounted) return false;

  switch (item.source.kind) {
    case SourceKind.image:
      unawaited(
        Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => ImageViewerScreen(path: path, title: item.title),
          ),
        ),
      );
      return true;

    case SourceKind.audio:
    case SourceKind.video:
      unawaited(
        Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => MediaPlayerScreen(
              path: path,
              title: item.title,
              isVideo: item.source.kind == SourceKind.video,
            ),
          ),
        ),
      );
      return true;

    case SourceKind.document:
      return _openDocument(context, item, path);

    case SourceKind.webPage:
      // La página archivada es un HTML de verdad, no texto extraído: se
      // muestra tal cual con su propio visor, en vez del lector de
      // documentos que espera Markdown.
      unawaited(
        Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => WebPageViewerScreen(path: path, title: item.title),
          ),
        ),
      );
      return true;

    case SourceKind.youtube:
      // El audio es un extra sobre la transcripción (ver
      // `YouTubeTranscriptTransformer`): si se pudo bajar, se puede
      // escuchar sin salir de la app.
      unawaited(
        Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => MediaPlayerScreen(
              path: path,
              title: item.title,
              isVideo: false,
            ),
          ),
        ),
      );
      return true;

    case SourceKind.socialPost:
      // Como con YouTube: si `SocialPostTransformer` consiguió bajar el
      // video del reel o la publicación, se puede ver sin salir de la app.
      unawaited(
        Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) =>
                MediaPlayerScreen(path: path, title: item.title, isVideo: true),
          ),
        ),
      );
      return true;

    case SourceKind.manualNote:
      // No trae un archivo original que mostrar aparte del contenido que
      // ya se ve en el propio detalle.
      return false;
  }
}

Future<bool> _openDocument(
  BuildContext context,
  KnowledgeItem item,
  String path,
) async {
  final format = await _sniffFormat(path);

  if (format == FileFormat.pdf) {
    if (!context.mounted) return false;
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(path: path, title: item.title),
        ),
      ),
    );
    return true;
  }

  // Para el resto de los documentos —DOCX, EPUB, texto suelto— se muestra
  // el contenido que ya extrajo el transformador correspondiente, en modo
  // de lectura: no hay razón para volver a leer el archivo si ya se sabe
  // qué dice.
  final rendition = item.renditions
      .whereType<TextRendition>()
      .where((r) => r.isPrimary)
      .firstOrNull;
  if (rendition == null || rendition.content.trim().isEmpty) return false;

  if (!context.mounted) return false;
  unawaited(
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            DocumentReaderScreen(title: item.title, content: rendition.content),
      ),
    ),
  );
  return true;
}

/// Lee solo el comienzo del archivo para reconocer su formato, en vez de
/// cargarlo entero en memoria: un video de varios cientos de megas no
/// tiene por qué pasar completo por acá solo para confirmar que es un
/// `.mp4`.
///
/// `RandomAccessFile.read()` y no `File.openRead()`: el stream con rango
/// de bytes deja el handle abierto hasta que algo lo cierre explícitamente
/// —acá no hay un `Stream.listen` que lo haga por su cuenta—, y en algunas
/// combinaciones de sistema de archivos eso alcanza para que la lectura
/// nunca se dé por terminada. Abrir, leer una vez y cerrar es lo mismo que
/// hace cualquier lectura parcial de archivo de toda la vida.
Future<FileFormat> _sniffFormat(String absolutePath) async {
  final file = File(absolutePath);
  final handle = await file.open();
  final Uint8List bytes;
  try {
    bytes = await handle.read(4096);
  } finally {
    await handle.close();
  }

  return detectFileFormat(bytes, name: p.basename(absolutePath));
}
