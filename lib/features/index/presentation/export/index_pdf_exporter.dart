import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sinapsis/core/pdf/pdf_bold.dart';
import 'package:sinapsis/features/index/domain/services/index_print.dart';

/// Quien lee una fuente de la app: `rootBundle.load` en la app; las pruebas
/// la leen del disco.
typedef IndexFontLoader = Future<ByteData> Function(String asset);

/// «Página 3 de 12», en el idioma de la app.
typedef IndexPageLabel = String Function(int page, int pages);

/// El PDF de «Descargar el índice» (F46, paso 4): un A4 listo para imprimir,
/// de texto de verdad —se busca, se copia, lo lee un lector de pantalla—, con
/// la tipografía del Índice en la pantalla:
///
/// - arriba, «Índice» y lo que se descargó (la forma, los niveles, la fecha);
/// - cada tema en versalitas, con su color de acento y un filete;
/// - cada documento en serif, con lo que dice debajo en chico;
/// - cada capítulo con su sangría por nivel, su número si se numera y **la
///   línea de puntos hasta su página**, como el índice de Word; los puntos
///   salen de una grilla contada desde el borde derecho, así quedan en columna
///   de un renglón al otro, y la página va en una columna fija a la derecha;
/// - al pie, «Página 3 de 12».
///
/// Usa las letras libres que viajan con la app (Lora para leer, Inter para
/// los rótulos): las tildes, la ñ, las comillas «» y las rayas salen bien —las
/// de fábrica del PDF solo tienen Latin-1—. El PDF se arma fuera del hilo de
/// la pantalla ([compute]): un índice de miles de capítulos son cientos de
/// páginas.
class IndexPdfExporter {
  const IndexPdfExporter({IndexFontLoader? fonts, IndexPdfWorker? worker})
    : _fonts = fonts,
      _worker = worker;

  final IndexFontLoader? _fonts;
  final IndexPdfWorker? _worker;

  static const _serifAsset = 'assets/fonts/Lora-Variable.ttf';
  static const _italicAsset = 'assets/fonts/Lora-Italic-Variable.ttf';
  static const _sansAsset = 'assets/fonts/InterVariable.ttf';

  Future<Uint8List> export(
    IndexPrint print, {
    required IndexPageLabel page,
  }) async {
    final load = _fonts ?? rootBundle.load;
    final fonts = (
      serif: await load(_serifAsset),
      italic: await load(_italicAsset),
      sans: await load(_sansAsset),
    );
    final job = (print: print, fonts: fonts, page: page);
    return (_worker ?? _offThread)(_build, job);
  }

  static Future<Uint8List> _offThread(
    Future<Uint8List> Function(IndexPdfJob job) build,
    IndexPdfJob job,
  ) => compute(build, job);
}

/// Lo que se le da a quien arma el PDF: los renglones, las letras y cómo se
/// dice «Página 3 de 12».
typedef IndexPdfJob = ({
  IndexPrint print,
  ({ByteData serif, ByteData italic, ByteData sans}) fonts,
  IndexPageLabel page,
});

/// Dónde se arma el PDF: en otro hilo en la app ([compute]); las pruebas de
/// pantalla, que corren con el reloj de mentira, lo arman en el mismo.
typedef IndexPdfWorker =
    Future<Uint8List> Function(
      Future<Uint8List> Function(IndexPdfJob job) build,
      IndexPdfJob job,
    );

/// La tinta, lo tenue y el acento sobre el papel blanco.
const _ink = PdfColor.fromInt(0xFF1C1B1F);
const _muted = PdfColor.fromInt(0xFF5E5A66);
const _faint = PdfColor.fromInt(0xFF9A96A3);
const _accent = PdfColor.fromInt(0xFF4F5BB5);

/// Lo que se corre cada nivel de capítulo.
const _levelIndent = 14.0;

/// El ancho de la columna de la página, a la derecha de los puntos.
const _pageColumn = 46.0;

/// Lo mínimo de puntos que se ve después de un título largo.
const _minLeader = 22.0;

/// Cada cuánto va un punto, y su tamaño.
const _dotStep = 4.2;
const _dotRadius = 0.55;

/// A qué altura del pie del renglón van los puntos: la línea de base.
const _dotBaseline = 2.6;

Future<Uint8List> _build(IndexPdfJob job) async {
  final serif = pw.Font.ttf(job.fonts.serif);
  final italic = pw.Font.ttf(job.fonts.italic);
  final sans = pw.Font.ttf(job.fonts.sans);
  final print = job.print;

  // La negrita no va en el estilo: se dibuja aislada con [PdfBold], así no
  // sigue en lo que viene después en la página (F46, paso 5f).
  pw.TextStyle sansStyle(double size, PdfColor color, {double spacing = 0}) =>
      pw.TextStyle(
        font: sans,
        fontSize: size,
        color: color,
        letterSpacing: spacing,
      );
  pw.TextStyle serifStyle(
    double size, {
    PdfColor color = _ink,
    bool italics = false,
  }) => pw.TextStyle(
    font: italics ? italic : serif,
    fontSize: size,
    color: color,
    lineSpacing: 2,
  );

  final document = pw.Document(
    title: print.title,
    subject: print.subtitle,
    creator: 'Sinapsis',
    producer: 'Sinapsis',
    theme: pw.ThemeData.withFont(
      base: serif,
      bold: serif,
      italic: italic,
      boldItalic: italic,
    ),
  );

  pw.Widget entry(IndexPrintLine line) {
    final level1 = line.level <= 1 && line.kind == IndexPrintKind.chapter;
    final color = line.context || line.level >= 3 ? _muted : _ink;
    final text = line.number == null
        ? line.title
        : '${line.number}  ${line.title}';
    final title = switch (line.kind) {
      IndexPrintKind.wholeText => pw.Text(
        text,
        style: serifStyle(10, color: _muted, italics: true),
      ),
      _ when level1 => PdfBold.text(text, serifStyle(10.5, color: color)),
      _ => pw.Text(text, style: serifStyle(10, color: color)),
    };
    final page = line.page;
    final indent = (line.level - 1).clamp(0, 12) * _levelIndent;
    return pw.Padding(
      padding: pw.EdgeInsets.only(left: indent, top: level1 ? 3 : 1.2),
      child: page == null
          ? title
          : pw.Stack(
              children: [
                // Los puntos, de un borde al otro del renglón, al pie: lo que
                // tapan el título y la página no se ve.
                pw.Positioned.fill(
                  child: pw.CustomPaint(
                    painter: (canvas, size) {
                      canvas.setFillColor(_faint);
                      // Desde el borde derecho de los puntos hacia atrás —la
                      // misma grilla en todos los renglones—, a la altura de
                      // la línea de base del último renglón del título (el
                      // origen es el pie del renglón).
                      for (
                        var x = size.x - _pageColumn - 3;
                        x > 0;
                        x -= _dotStep
                      ) {
                        canvas.drawEllipse(
                          x,
                          _dotBaseline,
                          _dotRadius,
                          _dotRadius,
                        );
                      }
                      canvas.fillPath();
                    },
                  ),
                ),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Expanded(
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.only(right: _minLeader),
                        child: pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Flexible(
                              child: pw.Container(
                                color: PdfColors.white,
                                padding: const pw.EdgeInsets.only(right: 3),
                                child: title,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    pw.SizedBox(
                      width: _pageColumn,
                      child: pw.Container(
                        color: PdfColors.white,
                        child: pw.Text(
                          page,
                          textAlign: pw.TextAlign.right,
                          style: sansStyle(8.5, _muted),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  pw.Widget line(IndexPrintLine line) => switch (line.kind) {
    IndexPrintKind.topic => pw.Container(
      margin: const pw.EdgeInsets.only(top: 18, bottom: 4),
      padding: const pw.EdgeInsets.only(bottom: 3),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _accent, width: 0.8)),
      ),
      child: PdfBold.text(
        line.title.toUpperCase(),
        sansStyle(9, _accent, spacing: 1.4),
      ),
    ),
    IndexPrintKind.document => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10, bottom: 2),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          PdfBold.text(line.title, serifStyle(12.5)),
          if (line.note case final note?)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 1),
              child: pw.Text(note, style: sansStyle(8, _muted)),
            ),
        ],
      ),
    ),
    _ => entry(line),
  };

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.copyWith(
        marginLeft: 62,
        marginRight: 62,
        marginTop: 56,
        marginBottom: 52,
      ),
      // Un índice de una biblioteca grande son cientos de páginas: el tope de
      // fábrica (20) dispararía `TooManyPagesException`.
      maxPages: 5000,
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 16),
        child: pw.Text(
          job.page(context.pageNumber, context.pagesCount),
          style: sansStyle(8, _muted),
        ),
      ),
      build: (context) => [
        PdfBold.text(print.title, serifStyle(26)),
        pw.SizedBox(height: 4),
        pw.Text(print.subtitle, style: sansStyle(9, _muted)),
        pw.SizedBox(height: 6),
        for (final l in print.lines) line(l),
      ],
    ),
  );
  return document.save();
}
