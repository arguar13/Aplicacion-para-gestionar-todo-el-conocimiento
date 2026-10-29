import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sinapsis/features/creations/design/creation_rasterizer.dart';
import 'package:sinapsis/features/creations/design/fit_text.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/templates/deck_style.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/slide_view.dart';

/// Los textos de las páginas de notas, ya traducidos por quien exporta.
@immutable
class DeckPdfLabels {
  const DeckPdfLabels({
    this.notesTitle = 'Notas del presentador',
    this.noNotes = 'Sin notas para esta diapositiva.',
    this.slideOf = _slideOf,
  });

  final String notesTitle;
  final String noNotes;

  /// «Diapositiva 3 de 12».
  final String Function(int number, int total) slideOf;

  static String _slideOf(int number, int total) =>
      'Diapositiva $number de $total';
}

/// El PDF de un mazo (F43, punto 5: «exportar a PDF»): una página por
/// diapositiva, con el diseño elegido, y si se pide, después de cada una, su
/// página de notas.
///
/// Cada diapositiva es la misma `SlideView` que se ve en pantalla, dibujada
/// fuera de pantalla a [DeckPdfExporter.export]`.pixelWidth` píxeles de
/// ancho (ver `CreationRasterizer`) y puesta como imagen en una página del
/// tamaño exacto de la diapositiva: el PDF es fiel por construcción —la
/// misma letra, los mismos fondos dibujados, el mismo ajuste del texto—, sin
/// un segundo dibujo hecho con otra librería que pueda desparejarse. El
/// costo es que el texto del PDF no se puede seleccionar.
///
/// Devuelve los bytes; guardarlos o compartirlos es de quien llama.
class DeckPdfExporter {
  const DeckPdfExporter();

  /// Puntos de PDF del alto de una página (el ancho sale del formato).
  static const double pageHeight = 540;

  Future<Uint8List> export({
    required SlideDeck deck,
    required DeckDesign design,
    bool includeSpeakerNotes = false,
    double pixelWidth = 1920,
    int jpegQuality = 90,
    SlideIllustrationResolver? illustrations,
    DeckPdfLabels labels = const DeckPdfLabels(),
  }) async {
    final logical = Size(
      design.aspect.logicalWidth,
      design.aspect.logicalHeight,
    );
    final ratio = pixelWidth / logical.width;
    final format = PdfPageFormat(pageHeight * design.aspect.ratio, pageHeight);

    // Las ilustraciones, cargadas antes: fuera de pantalla no hay un cuadro
    // siguiente que espere a que lleguen.
    if (illustrations != null) {
      for (final slide in deck.slides) {
        final reference = slide.illustrationRef;
        final provider = reference == null ? null : illustrations(reference);
        if (provider != null) await CreationRasterizer.precache(provider);
      }
    }

    final document = pw.Document(
      title: deck.title,
      creator: 'Sinapsis',
      producer: 'Sinapsis',
    );
    for (var i = 0; i < deck.slides.length; i++) {
      final slide = deck.slides[i];
      final slideImage = await _rasterize(
        SlideView(
          slide: slide,
          design: design,
          deck: deck,
          index: i,
          illustrations: illustrations,
        ),
        logical,
        ratio,
        jpegQuality,
      );
      _addImagePage(document, format, slideImage);
      if (includeSpeakerNotes) {
        final notesImage = await _rasterize(
          _NotesPage(
            deck: deck,
            design: design,
            index: i,
            labels: labels,
            illustrations: illustrations,
          ),
          logical,
          ratio,
          jpegQuality,
        );
        _addImagePage(document, format, notesImage);
      }
    }
    return document.save();
  }

  Future<Uint8List> _rasterize(
    Widget widget,
    Size logical,
    double ratio,
    int quality,
  ) async {
    final image = await CreationRasterizer.render(
      widget,
      logicalSize: logical,
      pixelRatio: ratio,
    );
    try {
      return await CreationRasterizer.toJpeg(image, quality: quality);
    } finally {
      image.dispose();
    }
  }

  void _addImagePage(
    pw.Document document,
    PdfPageFormat format,
    Uint8List jpg,
  ) {
    document.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Image(pw.MemoryImage(jpg), fit: pw.BoxFit.fill),
        ),
      ),
    );
  }
}

/// La página de notas de una diapositiva: la diapositiva en chico a la
/// izquierda y lo que se dice en voz alta a la derecha, en la letra del mazo
/// sobre blanco, para imprimir.
class _NotesPage extends StatelessWidget {
  const _NotesPage({
    required this.deck,
    required this.design,
    required this.index,
    required this.labels,
    this.illustrations,
  });

  final SlideDeck deck;
  final DeckDesign design;
  final int index;
  final DeckPdfLabels labels;
  final SlideIllustrationResolver? illustrations;

  static const _ink = Color(0xFF1C1E22);
  static const _muted = Color(0xFF5B606A);

  @override
  Widget build(BuildContext context) {
    final style = DeckStyle(design: design, deckTitle: deck.title);
    final fonts = style.fonts;
    final slide = deck.slides[index];
    final notes = slide.speakerNotes.trim();
    final width = design.aspect.logicalWidth;
    return ColoredBox(
      color: Colors.white,
      child: DefaultTextStyle(
        style: fonts.bodyStyle(size: 30, color: _ink),
        child: Padding(
          padding: const EdgeInsets.all(88),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: width * 0.4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      labels.slideOf(index + 1, deck.slides.length),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: fonts.bodyStyle(
                        size: 26,
                        color: _muted,
                        weight: 600,
                      ),
                    ),
                    const SizedBox(height: 24),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: const Color(0xFFD5D8DE),
                          width: 2,
                        ),
                      ),
                      child: AspectRatio(
                        aspectRatio: design.aspect.ratio,
                        child: SlideView(
                          slide: slide,
                          design: design,
                          deck: deck,
                          index: index,
                          illustrations: illustrations,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 72),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      labels.notesTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: fonts.displayStyle(size: 52, color: _ink),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 28),
                      height: 4,
                      width: 96,
                      alignment: Alignment.centerLeft,
                      color: style.palette.primary,
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: FitTextGroup(
                          minScale: 0.4,
                          items: [
                            for (final (i, paragraph)
                                in (notes.isEmpty
                                        ? [labels.noNotes]
                                        : notes.split(RegExp(r'\n+')))
                                    .indexed)
                              FitTextItem(
                                text: paragraph,
                                style: fonts.bodyStyle(
                                  size: 36,
                                  color: notes.isEmpty ? _muted : _ink,
                                  height: 1.45,
                                ),
                                gapBefore: i == 0 ? 0 : 22,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
