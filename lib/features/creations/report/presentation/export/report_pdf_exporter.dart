import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sinapsis/features/creations/report/domain/report.dart';
import 'package:sinapsis/features/creations/report/domain/report_keywords.dart';
import 'package:sinapsis/features/creations/report/domain/report_markdown.dart';
import 'package:sinapsis/features/creations/report/domain/report_markup.dart';
import 'package:sinapsis/features/creations/report/domain/report_order.dart';

/// Quien lee una fuente de la app: `rootBundle.load` en la app; las pruebas
/// pueden leerla del disco.
typedef ReportFontLoader = Future<ByteData> Function(String asset);

/// El PDF de un informe (F43, punto 5: «exportar a PDF»): un documento A4 de
/// texto de verdad —se puede buscar, copiar y leer con un lector de
/// pantalla—, con la misma estructura que el visor:
///
/// - arriba, la plantilla y el formato, el título, la bajada y las fuentes;
/// - cada sección con su número y su título, sus párrafos, viñetas, listas,
///   subtítulos y citas, y los términos del glosario;
/// - **las palabras clave en rosa** (decisión 85) y en negrita;
/// - en el interactivo, las preguntas de cada sección con sus opciones A, B,
///   C… —en el mismo orden que el visor— y, en una página aparte al final,
///   las respuestas con su explicación, para probarse en papel;
/// - al pie, el título y «Página 3 de 12».
///
/// Usa las fuentes libres que viajan con la app (Lora para leer, Inter para
/// los rótulos), así que las tildes, la ñ, las comillas «» y los guiones
/// largos salen bien —las de fábrica del PDF solo tienen Latin-1—. Los
/// archivos son variables y el PDF toma su cara normal: la negrita se dibuja
/// con el trazo del mismo contorno, como hacen los lectores de PDF con una
/// fuente sin su negrita.
class ReportPdfExporter {
  const ReportPdfExporter({ReportFontLoader? fonts}) : _fonts = fonts;

  final ReportFontLoader? _fonts;

  static const _bodyAsset = 'assets/fonts/Lora-Variable.ttf';
  static const _italicAsset = 'assets/fonts/Lora-Italic-Variable.ttf';
  static const _labelAsset = 'assets/fonts/InterVariable.ttf';

  /// El color del informe en papel: el ámbar de su ícono.
  static const accent = PdfColor.fromInt(0xFFA15C00);

  /// El rosa de las palabras clave, el de los temas claros (`StudyPalette`).
  static const keyword = PdfColor.fromInt(0xFFFFB3D9);

  static const _ink = PdfColor.fromInt(0xFF1F1B16);
  static const _muted = PdfColor.fromInt(0xFF5F5850);
  static const _panel = PdfColor.fromInt(0xFFF7F3EE);

  /// El ámbar al 14 % sobre el papel: el círculo del número de cada sección.
  static const _tint = PdfColor.fromInt(0xFFF2E8DB);

  static const double _body = 10.5;

  Future<Uint8List> export({
    required Report report,
    ReportKeywords keywords = ReportKeywords.empty,
    bool interactive = true,
    ReportExportLabels labels = const ReportExportLabels(),
  }) async {
    final load = _fonts ?? rootBundle.load;
    final serif = pw.Font.ttf(await load(_bodyAsset));
    final italic = pw.Font.ttf(await load(_italicAsset));
    final sans = pw.Font.ttf(await load(_labelAsset));
    final writer = _Writer(
      serif: serif,
      italic: italic,
      sans: sans,
      keywords: keywords,
    );

    final document = pw.Document(
      title: report.title,
      creator: 'Sinapsis',
      producer: 'Sinapsis',
      theme: pw.ThemeData.withFont(
        base: serif,
        bold: serif,
        italic: italic,
        boldItalic: italic,
      ),
    );
    final withAnswers = interactive && report.questionCount > 0;
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(
          marginLeft: 58,
          marginRight: 58,
          marginTop: 54,
          marginBottom: 54,
        ),
        // Sin este tope, un informe larguísimo dispararía
        // `TooManyPagesException` (el de fábrica es 20).
        maxPages: 1000,
        footer: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 18),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  report.title,
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                  style: writer.label(8, _muted),
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Text(
                labels.page(context.pageNumber, context.pagesCount),
                style: writer.label(8, _muted),
              ),
            ],
          ),
        ),
        build: (context) => [
          ...writer.header(report, labels),
          for (final (index, section) in report.sections.indexed)
            ...writer.section(
              section,
              number: index + 1,
              title: labels.sectionTitle(report, index),
              interactive: interactive,
              questionsTitle: labels.questions,
            ),
          if (withAnswers) ...[
            pw.NewPage(),
            ...writer.answerKey(report, labels),
          ],
        ],
      ),
    );
    return document.save();
  }
}

/// Lo que dibuja cada parte del PDF, con sus fuentes.
class _Writer {
  _Writer({
    required this.serif,
    required this.italic,
    required this.sans,
    required this.keywords,
  });

  final pw.Font serif;
  final pw.Font italic;
  final pw.Font sans;
  final ReportKeywords keywords;

  static const _accent = ReportPdfExporter.accent;
  static const _ink = ReportPdfExporter._ink;
  static const _muted = ReportPdfExporter._muted;
  static const _body = ReportPdfExporter._body;

  pw.TextStyle label(double size, PdfColor color, {double spacing = 0}) =>
      pw.TextStyle(
        font: sans,
        fontSize: size,
        color: color,
        letterSpacing: spacing,
      );

  pw.TextStyle text(
    double size, {
    PdfColor color = _ink,
    bool bold = false,
    bool italics = false,
    double lineSpacing = 3.2,
  }) => pw.TextStyle(
    font: italics ? italic : serif,
    fontSize: size,
    color: color,
    lineSpacing: lineSpacing,
    renderingMode: bold ? PdfTextRenderingMode.fillAndStroke : null,
  );

  List<pw.Widget> header(Report report, ReportExportLabels labels) => [
    if (labels.kicker.isNotEmpty)
      pw.Text(
        labels.kicker.toUpperCase(),
        style: label(8.5, _accent, spacing: 1.1),
      ),
    pw.SizedBox(height: 8),
    _Ink(
      color: _ink,
      stroke: 0.55,
      child: pw.Text(report.title, style: text(23, bold: true, lineSpacing: 4)),
    ),
    if (report.subtitle.isNotEmpty) ...[
      pw.SizedBox(height: 8),
      pw.Text(
        report.subtitle,
        style: text(12, color: _muted, italics: true, lineSpacing: 3),
      ),
    ],
    if (labels.sources.isNotEmpty) ...[
      pw.SizedBox(height: 8),
      pw.Text(labels.sources, style: label(8.5, _muted)),
    ],
    pw.SizedBox(height: 14),
    pw.Container(height: 1.2, color: _accent),
    pw.SizedBox(height: 10),
  ];

  List<pw.Widget> section(
    ReportSection section, {
    required int number,
    required String title,
    required bool interactive,
    required String questionsTitle,
  }) {
    final blocks = reportBlocksWithKeywords(section.body, keywords);
    final content = <pw.Widget>[
      ..._blocks(blocks),
      for (final (i, entry) in section.entries.indexed)
        _entry(entry, first: i == 0 && blocks.isEmpty),
      if (interactive && section.questions.isNotEmpty) ...[
        pw.SizedBox(height: 12),
        pw.Text(
          questionsTitle.toUpperCase(),
          style: label(8, _accent, spacing: 1),
        ),
        for (final (q, question) in section.questions.indexed) ...[
          pw.SizedBox(height: 6),
          _question(q + 1, question),
        ],
      ],
    ];
    // El título no queda solo al pie de una página: va junto con lo primero
    // que sigue, si es corto —un párrafo largo puede partirse entre páginas
    // y no se lo ata—.
    final first = blocks.isEmpty ? null : blocks.first.plainText.length;
    final keepWithFirst =
        content.isNotEmpty && (first == null || first <= _keepWithHeading);
    return [
      pw.SizedBox(height: 14),
      if (keepWithFirst)
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _heading(number, title),
            pw.SizedBox(height: 8),
            content.first,
          ],
        )
      else ...[
        _heading(number, title),
        pw.SizedBox(height: 8),
      ],
      ...content.skip(keepWithFirst ? 1 : 0),
    ];
  }

  /// Hasta cuántas letras tiene lo primero de una sección para ir pegado a
  /// su título.
  static const _keepWithHeading = 700;

  /// Un término del glosario con su definición, juntos.
  pw.Widget _entry(ReportEntry entry, {required bool first}) => pw.Padding(
    padding: pw.EdgeInsets.only(top: first ? 0 : 7),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _Ink(
          color: _accent,
          stroke: 0.32,
          child: pw.Text(
            entry.term,
            style: text(11.5, color: _accent, bold: true),
          ),
        ),
        if (entry.definition.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          _rich(
            withReportKeywords(parseReportInlines(entry.definition), keywords),
            text(_body),
          ),
        ],
      ],
    ),
  );

  /// Una pregunta con sus opciones, en su recuadro: cada una el suyo, así
  /// una sección con preguntas largas igual se reparte entre páginas.
  pw.Widget _question(int number, ReportQuestion question) => pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(12, 9, 12, 10),
    decoration: const pw.BoxDecoration(
      color: ReportPdfExporter._panel,
      borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _Ink(
          color: _ink,
          stroke: 0.25,
          child: pw.Text(
            '$number. ${question.question}',
            style: text(_body, bold: true),
          ),
        ),
        for (final (i, option) in reportOptionOrder(question).indexed) ...[
          pw.SizedBox(height: 3),
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 14),
            child: pw.Text(
              '${reportOptionLetter(i)}.  ${option.text}',
              style: text(_body - 0.5),
            ),
          ),
        ],
      ],
    ),
  );

  List<pw.Widget> answerKey(Report report, ReportExportLabels labels) => [
    _Ink(
      color: _ink,
      stroke: 0.45,
      child: pw.Text(labels.answerKey, style: text(18, bold: true)),
    ),
    pw.SizedBox(height: 6),
    pw.Container(height: 1.2, color: _accent),
    for (final (index, section) in report.sections.indexed)
      if (section.questions.isNotEmpty) ...[
        pw.SizedBox(height: 12),
        _Ink(
          color: _accent,
          stroke: 0.3,
          child: pw.Text(
            '${index + 1}. ${labels.sectionTitle(report, index)}',
            style: text(11.5, color: _accent, bold: true),
          ),
        ),
        for (final (q, question) in section.questions.indexed) ...[
          pw.SizedBox(height: 5),
          _answer(q + 1, question),
        ],
      ],
  ];

  pw.Widget _answer(int number, ReportQuestion question) {
    final order = reportOptionOrder(question);
    final letter = reportOptionLetter(order.indexOf(question.correct));
    return _rich([
      ReportInline('$number. $letter. ${question.correct.text}', bold: true),
      if (question.explanation.isNotEmpty)
        ReportInline(' — ${question.explanation}'),
    ], text(_body));
  }

  pw.Widget _heading(int number, String title) => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Container(
        width: 20,
        height: 20,
        alignment: pw.Alignment.center,
        decoration: const pw.BoxDecoration(
          color: ReportPdfExporter._tint,
          shape: pw.BoxShape.circle,
        ),
        child: pw.Text('$number', style: label(9, _accent)),
      ),
      pw.SizedBox(width: 9),
      pw.Expanded(
        child: _Ink(
          color: _ink,
          stroke: 0.4,
          child: pw.Text(title, style: text(15, bold: true, lineSpacing: 2)),
        ),
      ),
    ],
  );

  List<pw.Widget> _blocks(List<ReportBlock> blocks) {
    final widgets = <pw.Widget>[];
    ReportBlock? previous;
    for (final block in blocks) {
      final gap = switch ((previous, block)) {
        (null, _) => 0.0,
        (ReportBullet(), ReportBullet()) => 3.0,
        (_, ReportSubheading()) => 10.0,
        _ => 7.0,
      };
      if (gap > 0) widgets.add(pw.SizedBox(height: gap));
      widgets.add(_block(block));
      previous = block;
    }
    return widgets;
  }

  pw.Widget _block(ReportBlock block) => switch (block) {
    ReportParagraph() => _rich(block.inlines, text(_body)),
    ReportSubheading() => _rich(block.inlines, text(12, bold: true)),
    ReportQuote() => pw.Container(
      padding: const pw.EdgeInsets.only(left: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(left: pw.BorderSide(color: _accent, width: 2)),
      ),
      child: _rich(block.inlines, text(_body, italics: true)),
    ),
    ReportBullet(:final level, :final number) => pw.Padding(
      padding: pw.EdgeInsets.only(left: level * 16.0),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: number == null ? 13 : 18,
            child: pw.Text(
              number == null ? (level == 0 ? '•' : '–') : '$number.',
              style: text(_body, color: _accent),
            ),
          ),
          pw.Expanded(child: _rich(block.inlines, text(_body))),
        ],
      ),
    ),
  };

  /// Un párrafo con sus negritas, itálicas y palabras clave en rosa.
  ///
  /// Un texto entero en negrita —un subtítulo— va con el trazo puesto para
  /// el párrafo entero ([_Ink]). Dentro de un párrafo normal, cada palabra en
  /// negrita se dibuja sola ([_StrokedWord]): el modo de trazo del PDF queda
  /// puesto hasta que alguien lo cambia, y el paquete `pdf` no lo vuelve a
  /// «solo relleno» después de una palabra en negrita —todo lo que seguía en
  /// el párrafo salía en negrita—. Cada palabra guarda y repone el estado
  /// del dibujo, así que la negrita termina donde termina.
  pw.Widget _rich(List<ReportInline> inlines, pw.TextStyle base) {
    final allBold = base.renderingMode == PdfTextRenderingMode.fillAndStroke;
    final size = base.fontSize ?? _body;
    final spans = <pw.InlineSpan>[];
    for (final inline in inlines) {
      final emphasized = inline.bold || inline.keyword;
      if (allBold || !emphasized) {
        spans.add(
          pw.TextSpan(text: inline.text, style: _styleOf(inline, base)),
        );
        continue;
      }
      final font = inline.italic ? italic : (base.font ?? serif);
      for (final piece in RegExp(r'\S+|\s+').allMatches(inline.text)) {
        final word = piece[0]!;
        if (word.trim().isEmpty) {
          spans.add(pw.TextSpan(text: word, style: base));
          continue;
        }
        spans.add(
          pw.WidgetSpan(
            child: _StrokedWord(
              word,
              font: font,
              size: size,
              color: inline.keyword ? _ink : (base.color ?? _ink),
              background: inline.keyword ? ReportPdfExporter.keyword : null,
            ),
          ),
        );
      }
    }
    final paragraph = pw.RichText(
      overflow: pw.TextOverflow.span,
      text: pw.TextSpan(style: base, children: spans),
    );
    if (!allBold) return paragraph;
    return _Ink(
      color: base.color ?? _ink,
      stroke: size * 0.035,
      child: paragraph,
    );
  }

  /// El estilo de un pedazo que no se dibuja palabra por palabra: la
  /// itálica y, en un texto todo en negrita, el rosa de una palabra clave.
  pw.TextStyle _styleOf(ReportInline inline, pw.TextStyle base) {
    var style = base;
    if (inline.italic) style = style.copyWith(font: italic);
    if (inline.keyword) {
      style = style.copyWith(
        color: _ink,
        background: const pw.BoxDecoration(color: ReportPdfExporter.keyword),
      );
    }
    return style;
  }
}

/// Una palabra en negrita dentro de un párrafo: su contorno relleno y con
/// trazo, entre «guardar» y «reponer» el estado del dibujo, para que la
/// negrita no siga en lo que viene; con [background], el rosa de una
/// palabra clave detrás. Se apoya en la línea de base del párrafo.
class _StrokedWord extends pw.Widget {
  _StrokedWord(
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
      ..setLineWidth(size * 0.035)
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

/// Deja puesto el trazo con que se dibuja la negrita de lo de adentro: su
/// color —el de la tinta— y su grosor. Lo que no es negrita se dibuja solo
/// relleno y no lo usa.
class _Ink extends pw.SingleChildWidget {
  _Ink({required pw.Widget child, required this.color, required this.stroke})
    : super(child: child);

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
