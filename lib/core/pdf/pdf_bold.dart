/// La negrita de los PDF que arma la app (el Índice, un informe).
///
/// Las letras que viajan con la app son variables y el paquete `pdf` toma su
/// cara normal: la negrita se dibuja rellenando **y trazando** el contorno
/// (`PdfTextRenderingMode.fillAndStroke`, el modo `2 Tr` del PDF), como hace
/// un lector de PDF con una fuente que no trae su negrita.
///
/// El modo de dibujo del texto es parte del estado del dibujo del PDF y
/// queda puesto hasta que alguien lo cambia. El paquete `pdf` lo escribe solo
/// cuando no es el de relleno y nunca lo vuelve a «solo relleno»: eso llega
/// únicamente al comienzo de cada página. Un estilo con el trazo puesto
/// suelto dejaba en negrita todo lo que seguía en esa página (F46, paso 5f).
///
/// Por eso la negrita **nunca va en un estilo**: cada tramo en negrita se
/// dibuja aislado —se guarda el estado del dibujo, se dibuja con el trazo y
/// se lo repone (`q … Q`)— y lo que viene después sale solo relleno, como
/// tiene que salir:
///
/// - un texto entero en negrita —un título—, con [PdfBold] o [PdfBold.text];
/// - una palabra en negrita dentro de un párrafo que no lo es, con
///   [pdfBoldWords].
library;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// El grosor del trazo de la negrita, como fracción del tamaño de la letra.
const pdfBoldWeight = 0.03;

/// El grosor del trazo de la negrita de una letra de [size] puntos.
double pdfBoldStroke(double size) => size * pdfBoldWeight;

/// El tamaño de una letra sin tamaño en su estilo: el del tema de fábrica
/// del paquete `pdf`.
const _defaultSize = 12.0;

/// El texto entero de [child] en negrita, aislado del resto de la página: con
/// el trazo de [color] —el de la letra— y de [stroke] de grosor.
///
/// Lo de adentro hereda el trazo del tema, así que **todo** lo que dibuja va
/// en negrita: un pedazo que no tiene que ir —la llamada de una nota— no va
/// adentro, sino al lado de las palabras de [pdfBoldWords].
class PdfBold extends pw.StatelessWidget {
  PdfBold({required this.child, required this.color, required this.stroke});

  /// [text] en negrita con [style]: el trazo, del color de la letra y del
  /// grosor de su tamaño ([pdfBoldStroke]).
  factory PdfBold.text(
    String text,
    pw.TextStyle style, {
    pw.TextAlign? textAlign,
    int? maxLines,
    pw.TextOverflow? overflow,
  }) => PdfBold(
    color: style.color ?? PdfColors.black,
    stroke: pdfBoldStroke(style.fontSize ?? _defaultSize),
    child: pw.Text(
      text,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    ),
  );

  final pw.Widget child;
  final PdfColor color;
  final double stroke;

  @override
  pw.Widget build(pw.Context context) {
    final theme = pw.Theme.of(context);
    return _Isolated(
      color: color,
      stroke: stroke,
      child: pw.Theme(
        data: theme.copyWith(
          defaultTextStyle: theme.defaultTextStyle.copyWith(
            renderingMode: PdfTextRenderingMode.fillAndStroke,
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Dibuja [child] entre «guardar» y «reponer» el estado del dibujo, con el
/// trazo de [color] y [stroke] puesto: el modo de la negrita no sale de acá.
class _Isolated extends pw.SingleChildWidget {
  _Isolated({
    required pw.Widget child,
    required this.color,
    required this.stroke,
  }) : super(child: child);

  final PdfColor color;
  final double stroke;

  @override
  void paint(pw.Context context) {
    super.paint(context);
    context.canvas
      ..saveContext()
      ..setStrokeColor(color)
      ..setLineWidth(stroke);
    paintChild(context);
    context.canvas.restoreContext();
  }
}

/// [text] en negrita dentro de un párrafo que no lo es: cada palabra se
/// dibuja sola y aislada ([PdfBoldWord]) y los espacios, con [style], como
/// el resto del párrafo. Con [background], el fondo detrás de cada palabra
/// —el rosa de una palabra clave—.
List<pw.InlineSpan> pdfBoldWords(
  String text, {
  required pw.TextStyle style,
  required pw.Font font,
  PdfColor? background,
}) => [
  for (final piece in RegExp(r'\S+|\s+').allMatches(text))
    if (piece[0]!.trim().isEmpty)
      pw.TextSpan(text: piece[0], style: style)
    else
      pw.WidgetSpan(
        child: PdfBoldWord(
          piece[0]!,
          font: font,
          size: style.fontSize ?? _defaultSize,
          color: style.color ?? PdfColors.black,
          background: background,
        ),
      ),
];

/// Una palabra en negrita dentro de un párrafo: su contorno relleno y con
/// trazo, entre «guardar» y «reponer» el estado del dibujo, para que la
/// negrita no siga en lo que viene; con [background], ese color detrás. Se
/// apoya en la línea de base del párrafo.
class PdfBoldWord extends pw.Widget {
  PdfBoldWord(
    this.text, {
    required this.font,
    required this.size,
    required this.color,
    this.background,
  });

  final String text;
  final pw.Font font;
  final double size;
  final PdfColor color;
  final PdfColor? background;

  @override
  void layout(
    pw.Context context,
    pw.BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    final pdfFont = font.getFont(context);
    final metrics = pdfFont.stringMetrics(text) * size;
    box = PdfRect(0, 0, metrics.advanceWidth, pdfFont.ascent * size);
  }

  @override
  void paint(pw.Context context) {
    super.paint(context);
    final pdfFont = font.getFont(context);
    final at = box!;
    final canvas = context.canvas..saveContext();
    if (background != null) {
      final descent = pdfFont.descent * size;
      canvas
        ..setFillColor(background)
        ..drawRect(at.left, at.bottom + descent, at.width, at.height - descent)
        ..fillPath();
    }
    canvas
      ..setFillColor(color)
      ..setStrokeColor(color)
      ..setLineWidth(pdfBoldStroke(size))
      ..drawString(
        pdfFont,
        size,
        text,
        at.left,
        at.bottom,
        mode: PdfTextRenderingMode.fillAndStroke,
      )
      ..restoreContext();
  }
}
