import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/app_snack_bar.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/storage/file_opener.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_study_actions.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_study_bar.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_contents_sheet.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_frame.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_more_sheet.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note_target.dart';
import 'package:sinapsis/features/text_notes/presentation/widgets/text_notes_list_sheet.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_reader_view.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/mobile_page_width.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/pdf_viewer_view.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/web_page_viewer_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// En qué visor se ve un original.
enum OriginalFormat {
  /// Un PDF, con su página de verdad.
  pdf,

  /// Una página web archivada, como en el navegador del teléfono.
  page,

  /// Un Word, un EPUB, un texto o un Markdown, como libro paginado.
  reader,
}

/// Cómo se dice y qué cambia «Apariencia» en cada formato.
extension OriginalFormatPresentation on OriginalFormat {
  String label(AppLocalizations l10n) => switch (this) {
    OriginalFormat.pdf => l10n.f47P1KindPdf,
    OriginalFormat.page => l10n.f47P1KindWebPage,
    OriginalFormat.reader => l10n.f47P1KindBook,
  };

  IconData get icon => switch (this) {
    OriginalFormat.pdf => Icons.picture_as_pdf_outlined,
    OriginalFormat.page => Icons.public,
    OriginalFormat.reader => Icons.menu_book_outlined,
  };

  ReadingBodyKind get bodyKind => switch (this) {
    OriginalFormat.pdf => ReadingBodyKind.page,
    OriginalFormat.page => ReadingBodyKind.asIs,
    OriginalFormat.reader => ReadingBodyKind.text,
  };
}

/// Un original a pantalla completa, **el mismo en Procesado y en la
/// Biblioteca** (F45, paso 7b, mejora 16, decisión H), en **el marco de
/// lectura** (F47, paso 1): ←, Contenido, IA, Aa y ⋮ arriba; en la fila de
/// IA, las tres fichas donde se marca —Resumir · Sintetizar · Palabras clave,
/// con la IA o a mano ([OriginalStudyBar])—, Preguntar a la IA y Podcast; el
/// título grande; [body] —casi siempre un [OriginalView]— y el lugar del
/// reproductor abajo, sin el botón flotante.
///
/// Lo abren el documento procesado, sobre su copia
/// (`ProcessedOriginalScreen`), y la vista previa del detalle de una fuente,
/// sobre la fuente (`openDocumentViewer`). Cada uno pone lo suyo en
/// «Contenido» y en ⋮: en Procesado, «Descargar con lo marcado» y, en rojo,
/// «Borrar la copia del original»; de la Biblioteca nada se borra.
class OriginalScreen extends ConsumerWidget {
  const OriginalScreen({
    required this.title,
    required this.format,
    required this.body,
    this.study,
    this.kindLabel,
    this.contents = const [],
    this.menu = const [],
    this.podcastScope,
    super.key,
  });

  final String title;

  /// En qué visor se ve: lo que dice el tipo y lo que cambia «Apariencia».
  final OriginalFormat format;

  /// Lo de abajo del título: casi siempre un [OriginalView]; mientras se
  /// carga la copia, o si falta, lo que lo dice.
  final Widget body;

  /// Dónde se marca, o `null` si no se marca: la fila de IA lleva solo
  /// Preguntar a la IA y Podcast.
  final OriginalStudy? study;

  /// El tipo dicho de otra manera que el formato —«Foto»—; sin esto, el del
  /// formato.
  final String? kindLabel;

  final List<ReadingContentsSection> contents;
  final List<ReadingMenuGroup> menu;

  /// Sobre qué se arma un podcast desde su ficha: el documento procesado;
  /// `null` en una fuente de la Biblioteca (ver [ReadingFrame.podcastScope]).
  final CreationScope? podcastScope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final study = this.study;
    // Eligiendo a mano, la línea que lo dice está en la fila de IA: no se
    // cierra hasta «Listo».
    final picking =
        study != null &&
        ref.watch(
          studyViewProvider(
            study.original.renditionId,
          ).select((view) => view.pick != null),
        );

    return ReadingFrame(
      key: const Key('original-screen'),
      info: ReadingDocumentInfo(
        title: title,
        kindLabel: kindLabel ?? format.label(l10n),
        kindIcon: format.icon,
      ),
      bodyKind: format.bodyKind,
      body: body,
      aiRow: study == null
          ? null
          : (context, trailing) =>
                OriginalStudyBar(study: study, trailing: trailing),
      aiRowPinned: picking,
      onSummarize: study == null
          ? null
          : () => unawaited(
              tapOriginalStudy(ref, context, study, StudyMarkKind.summary),
            ),
      contents: contents,
      menu: menu,
      podcastScope: podcastScope,
    );
  }
}

/// Lo que se ve de un original (F45, paso 7b): **arriba, donde se marca**
/// —las tres fichas de Resumen, Síntesis y Palabras clave, con la IA o a mano
/// ([OriginalStudyPanel])—, y debajo **el visor de siempre** con lo marcado
/// encima y el lector flotante, con «Leer: Todo · Resumen · Síntesis ·
/// Palabras clave»:
///
/// - un PDF, con su página de verdad (`PdfViewerView`);
/// - una página web, como en el navegador del teléfono también en la
///   computadora (F45, paso 4, decisión D: `MobilePageWidth`);
/// - un Word, un EPUB o un texto, como libro paginado, con A− A+ y el paso de
///   página (`DocumentReaderView`).
///
/// Sin [study] no hay barra arriba, y con [notice] una línea si hay algo que
/// contar —en Procesado, que la fuente cambió su texto—. Un libro sin texto
/// ([text] `null`) no tiene qué mostrar en el lector: se ofrece abrirlo con
/// otra app ([OriginalUnreadable]).
///
/// **En el marco de lectura** (F47, paso 1: [OriginalScreen]) va sin
/// [study]: las fichas van en la fila de IA del marco, no arriba del visor.
/// Con [study] —la pantalla de cortes del triaje— las lleva arriba, como
/// antes.
class OriginalView extends StatelessWidget {
  const OriginalView({
    required this.format,
    required this.title,
    this.path,
    this.url,
    this.text,
    this.study,
    this.notice,
    super.key,
  }) : assert(
         study == null || text != null,
         'se marca sobre el texto que el visor pinta',
       ),
       assert(
         format == OriginalFormat.reader || path != null,
         'un PDF o una página se ven desde su archivo',
       );

  final OriginalFormat format;

  /// Dónde está el archivo: el PDF, la página o, en el lector, el original
  /// para abrirlo con otra app si no tiene texto. El lector de un texto
  /// extraído —el de un audio o una foto— no lo necesita.
  final String? path;
  final String title;

  /// La dirección de una página web, para las fotos que no quedaron
  /// guardadas.
  final String? url;

  /// El texto que el visor pinta y lee en voz alta.
  final StudyText? text;

  /// Dónde se marca, o `null` si no se marca.
  final OriginalStudy? study;

  /// Por qué no hay marcas, si hay algo que decir.
  final String? notice;

  @override
  Widget build(BuildContext context) {
    final study = this.study;
    final notice = this.notice;
    final text = this.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (study != null)
          OriginalStudyPanel(study: study)
        else if (notice != null)
          OriginalNotice(message: notice),
        Expanded(
          child: switch (format) {
            OriginalFormat.pdf => _NotesOnPage(
              text: text,
              child: PdfViewerView(path: path!, text: text, title: title),
            ),
            OriginalFormat.page => _NotesOnPage(
              text: text,
              child: MobilePageWidth(
                child: WebPageViewerView(
                  path: path!,
                  url: url,
                  text: text,
                  title: title,
                  readAloud: true,
                  mobile: true,
                ),
              ),
            ),
            OriginalFormat.reader when text == null =>
              path == null
                  ? const SizedBox.shrink()
                  : OriginalUnreadable(path: path!),
            OriginalFormat.reader => SafeArea(
              top: false,
              child: DocumentReaderView(
                title: title,
                content: text!.content,
                markdown: text.markdown,
                study: text,
                // Fuera del marco —la pantalla de cortes— está el botón
                // flotante: que no tape «siguiente».
                controlsAtBottom: study != null,
              ),
            ),
          },
        ),
      ],
    );
  }
}

/// Las notas en el texto de un original que se ve como página —un PDF, una
/// página web— (F45, paso 8b): se ponen con «Nota» en la barrita de la
/// selección, que la ubica en el texto extraído como un resaltado, y se ven
/// en «Notas (N)» de ⋮; sobre la página no van globitos. Sin texto, ninguna.
class _NotesOnPage extends StatelessWidget {
  const _NotesOnPage({required this.text, required this.child});

  final StudyText? text;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = this.text;
    return ReadingNotesOffer(
      sources: [
        if (text != null)
          TextNoteSource(
            target: textNoteTargetOf(text),
            content: text.content,
            onPage: true,
          ),
      ],
      child: child,
    );
  }
}

/// Las tres fichas de estudio arriba del visor, sobre el color de la barra.
/// Con la letra grande pueden ocupar varios renglones: se desplazan dentro de
/// un alto acotado y el original sigue a la vista.
class OriginalStudyPanel extends StatelessWidget {
  const OriginalStudyPanel({required this.study, super.key});

  final OriginalStudy study;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return Material(
      key: const Key('original-study-panel'),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height * 0.42),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: OriginalStudyBar(study: study),
        ),
      ),
    );
  }
}

/// Una línea arriba del visor que dice por qué no hay marcas.
class OriginalNotice extends StatelessWidget {
  const OriginalNotice({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      key: const Key('processed-original-notice'),
      color: colors.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 20, color: colors.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un Word, un EPUB o un texto cuyo texto ya no es el de la fuente: el lector
/// no tiene qué mostrar, y se ofrece abrirlo con otra app. En el original
/// entero y en su vista previa del documento (`ProcessedOriginalSection`).
class OriginalUnreadable extends ConsumerWidget {
  const OriginalUnreadable({required this.path, super.key});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return EmptyStateView(
      icon: Icons.description_outlined,
      title: l10n.processedOriginalUnreadable,
      actionLabel: l10n.processedOriginalOpenWith,
      onAction: () => unawaited(_open(context, ref)),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(fileOpenerProvider).open(path);
    final message = switch (result) {
      FileOpenResult.done => null,
      FileOpenResult.noAppAvailable => l10n.contentNoAppToOpen,
      FileOpenResult.fileNotFound ||
      FileOpenResult.failed => l10n.contentOpenFailed,
    };
    if (message == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showAppSnackBar(AppSnackBar(content: Text(message)));
  }
}
