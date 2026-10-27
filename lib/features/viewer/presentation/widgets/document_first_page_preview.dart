import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/features/organize/presentation/hand_highlighting.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/features/viewer/domain/services/reader_pagination.dart';

/// La primera página de un documento de texto —un DOCX, un EPUB, un `.txt`,
/// un `.md`—, quieta, como vista previa en el detalle del elemento (F39).
///
/// **Por qué no es un `DocumentReaderView` con el scroll apagado.** El lector
/// arma un `PageView` con un `SingleChildScrollView` adentro de cada página y
/// un `SelectableText`: tres cosas que toman gestos, y el que más se nota es
/// el arrastre vertical, que mueve el texto de la página en vez del detalle
/// donde está la vista previa. Apagarlos uno por uno deja un lector entero
/// armado —con su lector en voz alta, sus controles de página, su barra de
/// estudiar— solo para mirar una hoja. Esto es la hoja y nada más: un texto
/// que no se desplaza, no se selecciona y no pide ningún gesto, de modo que
/// arrastrar encima desplaza el detalle, como arrastrar sobre cualquier otro
/// renglón. Un toque abre el lector a pantalla completa ([onTap]), donde sí
/// se lee, se resalta y se pasa de página.
///
/// Es la misma tarjeta con forma de página que la del lector, y pinta lo
/// estudiado (F36) y lo resaltado a mano (F38) que cae en esta página, con sus
/// colores. Lo que se lee en voz alta no: eso se ve en el lector.
class DocumentFirstPagePreview extends ConsumerStatefulWidget {
  const DocumentFirstPagePreview({
    required this.content,
    required this.onTap,
    this.markdown = true,
    this.study,
    super.key,
  });

  final String content;

  /// Si [content] es Markdown y se muestra con formato, o texto tal cual
  /// (F22): ver `TextResolvedViewer.markdown`.
  final bool markdown;

  /// El texto que se estudia, si [content] es ese texto (F36).
  final StudyText? study;

  /// Tocar la hoja: abrir el lector.
  final VoidCallback? onTap;

  @override
  ConsumerState<DocumentFirstPagePreview> createState() =>
      _DocumentFirstPagePreviewState();
}

class _DocumentFirstPagePreviewState
    extends ConsumerState<DocumentFirstPagePreview> {
  /// La primera página y dónde empieza en [DocumentFirstPagePreview.content],
  /// armada una vez por texto: lo estudiado y lo resaltado se redibuja sin
  /// volver a cortar el libro.
  late ({String text, int start}) _page = _firstPage();

  /// Solo el comienzo del libro se parte: abrir el detalle de uno de millones
  /// de caracteres cuesta lo mismo que el de uno corto.
  ({String text, int start}) _firstPage() {
    final first = firstReaderPageRange(widget.content);
    if (first == null) return (text: '', start: 0);
    return (
      text: widget.content.substring(first.start, first.end),
      start: first.start,
    );
  }

  @override
  void didUpdateWidget(covariant DocumentFirstPagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.content != oldWidget.content) _page = _firstPage();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final page = _page;
    if (page.text.isEmpty) return const SizedBox.shrink();

    final study = widget.study;
    final end = page.start + page.text.length;
    final paints = study == null
        ? const <PaintedRange>[]
        : paintsWithin(
            watchStudyPaints(ref, context, study.renditionId),
            page.start,
            end,
          );
    final marks = study == null
        ? const <HandMark>[]
        : handMarks(
            context,
            [
              for (final highlight
                  in ref
                          .watch(renditionHighlightsProvider(study.renditionId))
                          .valueOrNull ??
                      const <Highlight>[])
                // Los que ya no entran en el texto —la forma se regeneró— no
                // se pintan.
                if (highlight.endOffset <= study.content.length) highlight,
            ],
            from: page.start,
            to: end,
          );
    final rendered = widget.markdown
        ? RenderedMarkdown.parse(page.text)
        : RenderedMarkdown.plain(page.text);

    return GestureDetector(
      key: const Key('document-first-page-preview'),
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.shadow.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            // Lo que no entra en la hoja se corta: no se desplaza.
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minHeight: 0,
                maxHeight: double.infinity,
                child: Text.rich(
                  rendered.buildSpans(
                    theme,
                    const [],
                    baseStyle: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                    paints: paints,
                    marks: marks,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
