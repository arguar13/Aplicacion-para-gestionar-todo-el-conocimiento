import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/pdf_study_overlay.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La primera página de un PDF, quieta, como vista previa en el detalle del
/// elemento (F39).
///
/// **Por qué no es un `PdfViewerView` con el desplazamiento apagado.** El
/// visor de `pdfrx` es un `InteractiveViewer` con su propio manejo de gestos:
/// el arrastre vertical es suyo —mueve el documento, no la pantalla— y, aun
/// con el paneo y el zoom apagados, queda armado un visor entero con su
/// controlador, su selección de texto y su paginado para mirar una hoja.
/// `PdfPageView` es el otro extremo de la misma librería: una imagen de la
/// página 1, renderizada con el mismo PDFium, sin ningún reconocedor de
/// gestos. Arrastrar encima desplaza el detalle y un toque abre el visor de
/// verdad ([onTap]), a pantalla completa, donde se hace zoom, se pasa de
/// página, se selecciona y se resalta.
///
/// Se ve la página entera —sin recortar—, a lo ancho o a lo alto de lo que
/// entre en el marco, y se renderiza una sola vez a su tamaño: no se carga el
/// resto del documento.
///
/// Con [text], lo estudiado (F36) y lo resaltado a mano (F38) que cae en la
/// página 1 se pinta sobre sus letras, con [PdfStudyOverlay], igual que en el
/// visor.
class PdfFirstPagePreview extends ConsumerStatefulWidget {
  const PdfFirstPagePreview({
    required this.path,
    required this.onTap,
    this.text,
    super.key,
  });

  final String path;

  /// El texto extraído del PDF y su forma, si tiene: de ahí sale lo estudiado.
  final StudyText? text;

  /// Tocar la hoja: abrir el visor.
  final VoidCallback? onTap;

  @override
  ConsumerState<PdfFirstPagePreview> createState() =>
      _PdfFirstPagePreviewState();
}

class _PdfFirstPagePreviewState extends ConsumerState<PdfFirstPagePreview> {
  /// Para que la página se redibuje cuando [_study] termina de leer sus
  /// letras.
  final _repaint = _Repaint();
  late final PdfStudyOverlay _study = PdfStudyOverlay.fixed(
    onRepaint: _repaint.notify,
  );

  @override
  void dispose() {
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    if (text != null) {
      _study.update(
        content: text.content,
        // La página de un PDF es blanca también en modo oscuro.
        paints: watchStudyPaints(
          ref,
          context,
          text.renditionId,
          brightness: Brightness.light,
        ),
        scannedNotice: AppLocalizations.of(context)!.studyScannedPage,
        highlights:
            ref
                .watch(renditionHighlightsProvider(text.renditionId))
                .valueOrNull ??
            const [],
      );
    }
    final theme = Theme.of(context);
    return GestureDetector(
      key: const Key('pdf-first-page-preview'),
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: PdfDocumentViewBuilder.file(
        widget.path,
        errorBuilder: (context, error, stackTrace) => Center(
          child: Icon(
            Icons.picture_as_pdf_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        builder: (context, document) => Padding(
          padding: const EdgeInsets.all(12),
          child: PdfPageView(
            document: document,
            pageNumber: 1,
            decorationBuilder: (context, pageSize, page, pageImage) => Center(
              child: AspectRatio(
                aspectRatio: pageSize.width / pageSize.height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.shadow.withValues(alpha: 0.25),
                        blurRadius: 6,
                        offset: const Offset(1, 2),
                      ),
                    ],
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ?pageImage,
                      if (text != null)
                        CustomPaint(
                          painter: _StudyPainter(_study, page, _repaint),
                        ),
                    ],
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

/// Un aviso de «volvé a dibujar» para [_StudyPainter]: `notifyListeners` es
/// protegido.
class _Repaint extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// Lo estudiado de la página, pintado sobre su imagen.
class _StudyPainter extends CustomPainter {
  _StudyPainter(this._study, this._page, Listenable repaint)
    : super(repaint: repaint);

  final PdfStudyOverlay _study;
  final PdfPage _page;

  @override
  void paint(Canvas canvas, Size size) =>
      _study.paintPage(canvas, Offset.zero & size, _page);

  @override
  bool shouldRepaint(covariant _StudyPainter oldDelegate) => true;
}
