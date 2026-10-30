import 'package:flutter/material.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_frame.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_reader_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Un texto como libro paginado a pantalla completa, en **el marco de
/// lectura** (F47, paso 1): un Word, un EPUB, un texto o un Markdown que no
/// es el original de un documento —un adjunto, un texto que no se estudia—.
///
/// Envoltorio delgado sobre [DocumentReaderView]: todo el lector de verdad
/// vive ahí, para poder embeberlo también directo en el detalle de un
/// elemento sin pasar por esta pantalla ni por `Navigator`. La letra y su
/// tamaño son los de «Apariencia»; los capítulos, los de «Contenido».
class DocumentReaderScreen extends StatelessWidget {
  const DocumentReaderScreen({
    required this.title,
    required this.content,
    this.markdown = true,
    this.study,
    super.key,
  });

  final String title;
  final String content;

  /// Ver `TextResolvedViewer.markdown`.
  final bool markdown;

  /// Ver `TextResolvedViewer.study`.
  final StudyText? study;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ReadingFrame(
      info: ReadingDocumentInfo(
        title: title,
        kindLabel: l10n.f47P1KindBook,
        kindIcon: Icons.menu_book_outlined,
      ),
      body: DocumentReaderView(
        title: title,
        content: content,
        markdown: markdown,
        study: study,
      ),
    );
  }
}
