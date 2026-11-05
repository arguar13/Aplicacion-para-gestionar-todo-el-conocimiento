import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_frame.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note_target.dart';
import 'package:sinapsis/features/text_notes/presentation/widgets/text_notes_list_sheet.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_reader_view.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/image_viewer_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Una foto o un escaneo a pantalla completa, en **el marco de lectura** (F47,
/// paso 1): la imagen —con su zoom y su tono en «Apariencia»— y, si se leyó
/// texto en ella, **el texto que se leyó**, a un toque: «Imagen · Texto».
/// El texto es el que se estudia, con sus marcas, lo resaltado a mano y
/// «Escuchar».
///
/// Envoltorio delgado sobre [ImageViewerView] y [DocumentReaderView]: la
/// imagen se embebe también en el detalle de un elemento —ver
/// `EmbeddedFileViewer`—.
class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({
    required this.path,
    required this.title,
    this.text,
    super.key,
  });

  final String path;
  final String title;

  /// El texto que se leyó en la imagen, si se leyó alguno.
  final StudyText? text;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final text = this.text;
    return ReadingFrame(
      info: ReadingDocumentInfo(
        title: title,
        kindLabel: l10n.f47P1KindImage,
        kindIcon: Icons.image_outlined,
        thumbnail: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.file(
            File(path),
            fit: BoxFit.cover,
            cacheWidth: 168,
            errorBuilder: (context, error, stackTrace) =>
                const Icon(Icons.image_outlined),
          ),
        ),
      ),
      bodyKind: text == null
          ? ReadingBodyKind.page
          : ReadingBodyKind.pageWithText,
      body: text == null
          ? ImageViewerView(path: path)
          : _ImageWithText(path: path, title: title, text: text),
    );
  }
}

/// La imagen y el texto que se leyó en ella, uno u otro, con «Imagen ·
/// Texto» arriba.
class _ImageWithText extends StatefulWidget {
  const _ImageWithText({
    required this.path,
    required this.title,
    required this.text,
  });

  final String path;
  final String title;
  final StudyText text;

  @override
  State<_ImageWithText> createState() => _ImageWithTextState();
}

class _ImageWithTextState extends State<_ImageWithText> {
  var _showText = false;

  /// Ir a una nota desde la imagen: pasa a «Texto» y, ya armado el texto,
  /// le pide a él que la muestre.
  bool _revealInText(int start, int end) {
    final frame = ReadingFrameController.maybeOf(context);
    setState(() => _showText = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // El texto se ofrece después de su primer cuadro.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final source in frame?.noteSources ?? const <TextNoteSource>[]) {
          if (!source.onPage) source.reveal?.call(start, end);
        }
      });
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SegmentedButton<bool>(
            key: const Key('image-text-toggle'),
            segments: [
              ButtonSegment(
                value: false,
                icon: const Icon(Icons.image_outlined),
                label: Text(l10n.f47P1ImageTab),
              ),
              ButtonSegment(
                value: true,
                icon: const Icon(Icons.notes_outlined),
                label: Text(l10n.f47P1ImageTextTab),
              ),
            ],
            selected: {_showText},
            onSelectionChanged: (selected) =>
                setState(() => _showText = selected.single),
          ),
        ),
        Expanded(
          child: _showText
              ? DocumentReaderView(
                  key: const Key('image-text'),
                  title: widget.title,
                  content: widget.text.content,
                  markdown: widget.text.markdown,
                  study: widget.text,
                )
              // La imagen sola lleva el tono de la página: la letra del
              // texto va con el modo. Sus notas (F45, paso 8b) son las del
              // texto: desde «Notas (N)», ir a una pasa a «Texto».
              : ReadingNotesOffer(
                  sources: [
                    TextNoteSource(
                      target: textNoteTargetOf(widget.text),
                      content: widget.text.content,
                      onPage: true,
                      reveal: _revealInText,
                    ),
                  ],
                  child: ReadingPageTone(
                    bodyKind: ReadingBodyKind.page,
                    child: ImageViewerView(path: widget.path),
                  ),
                ),
        ),
      ],
    );
  }
}
