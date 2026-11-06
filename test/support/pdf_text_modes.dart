import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Una palabra que un PDF dibuja, con el modo de dibujo del texto con que
/// sale (`0` solo relleno, `2` relleno y trazo: la negrita de la app), en
/// cuántos «guardar el estado» (`q`) está metida, el tamaño de su letra, su
/// color de relleno y el del trazo (`r g b`) y el grosor del trazo.
typedef PdfShownWord = ({
  String text,
  int mode,
  int depth,
  double size,
  String fill,
  String stroke,
  double width,
});

/// Lo que guarda `q` y repone `Q`.
typedef _DrawState = ({int mode, String fill, String stroke, double width});

/// Lo que dibuja cada página de [pdf], en orden, leído del flujo de dibujo
/// mismo —el que arma el paquete `pdf`: comprimido, con letras de dos bytes
/// (`Identity-H`) y su `ToUnicode` para saber qué letra es cada una—.
///
/// El estado se sigue como lo sigue un lector de PDF: `n Tr` cambia el modo,
/// `rg` y `RG` los colores, `w` el grosor; `q` guarda el estado del dibujo y
/// `Q` lo repone; cada página empieza con el de relleno, en negro y con
/// grosor 1. Así se ve si una negrita quedó puesta en lo que sigue. Un `Q`
/// sin su `q`, o un `q` que queda sin reponer al terminar la página, es un
/// error ([StateError]).
List<List<PdfShownWord>> pdfShownWords(Uint8List pdf) {
  final file = latin1.decode(pdf);
  final objects = <int, ({String head, Uint8List? stream})>{};
  final starts = RegExp(r'(\d+) 0 obj').allMatches(file).toList();
  for (var i = 0; i < starts.length; i++) {
    final from = starts[i].end;
    final to = file.indexOf('endobj', from);
    final body = file.substring(from, to);
    final open = RegExp(r'>>\s*stream\r?\n').firstMatch(body);
    Uint8List? stream;
    var head = body;
    if (open != null) {
      head = body.substring(0, open.start + 2);
      final at = from + open.end;
      final end = file.indexOf('endstream', at);
      final raw = pdf.sublist(at, end);
      stream = Uint8List.fromList(
        head.contains('/FlateDecode') ? zlib.decode(raw) : raw,
      );
    }
    objects[int.parse(starts[i][1]!)] = (head: head, stream: stream);
  }

  Map<String, String> cmapOf(int font) {
    final ref = RegExp(r'/ToUnicode (\d+) 0 R').firstMatch(objects[font]!.head);
    if (ref == null) return const {};
    final text = latin1.decode(objects[int.parse(ref[1]!)]!.stream!);
    return {
      for (final pair in RegExp(
        r'<([0-9A-Fa-f]{4})>\s*<([0-9A-Fa-f]+)>',
      ).allMatches(text))
        pair[1]!.toUpperCase(): String.fromCharCodes([
          for (var i = 0; i < pair[2]!.length; i += 4)
            int.parse(pair[2]!.substring(i, i + 4), radix: 16),
        ]),
    };
  }

  final pages = <List<PdfShownWord>>[];
  final pageObjects = objects.values.where(
    (o) => RegExp(r'/Type\s*/Page(?![s\w])').hasMatch(o.head),
  );
  for (final page in pageObjects) {
    final fonts = <String, Map<String, String>>{
      for (final font in RegExp(r'/(F\d+) (\d+) 0 R').allMatches(page.head))
        font[1]!: cmapOf(int.parse(font[2]!)),
    };
    final contents = RegExp(r'/Contents (\d+) 0 R').firstMatch(page.head)!;
    final content = latin1.decode(objects[int.parse(contents[1]!)]!.stream!);
    final words = <PdfShownWord>[];
    final saved = <_DrawState>[];
    var state = (mode: 0, fill: '0 0 0', stroke: '0 0 0', width: 1.0);
    var font = const <String, String>{};
    var size = 0.0;
    final operands = <String>[];
    String color() => operands.sublist(operands.length - 3).join(' ');
    String decode(String token) {
      final hex = token.substring(1, token.length - 1).toUpperCase();
      return [
        for (var i = 0; i + 4 <= hex.length; i += 4)
          font[hex.substring(i, i + 4)] ?? '?',
      ].join();
    }

    for (final token in RegExp(
      r'\[[^\]]*\]|<[0-9A-Fa-f]*>|\((?:\\.|[^\\)])*\)|/[^\s/\[\]<>()]+|[^\s\[\]<>()/]+',
    ).allMatches(content).map((m) => m[0]!)) {
      switch (token) {
        case 'q':
          saved.add(state);
        case 'Q':
          if (saved.isEmpty) {
            throw StateError('Q sin un q antes en la página ${pages.length}');
          }
          state = saved.removeLast();
        case 'Tr':
          state = (
            mode: int.parse(operands.last),
            fill: state.fill,
            stroke: state.stroke,
            width: state.width,
          );
        case 'rg':
          state = (
            mode: state.mode,
            fill: color(),
            stroke: state.stroke,
            width: state.width,
          );
        case 'RG':
          state = (
            mode: state.mode,
            fill: state.fill,
            stroke: color(),
            width: state.width,
          );
        case 'w':
          state = (
            mode: state.mode,
            fill: state.fill,
            stroke: state.stroke,
            width: double.parse(operands.last),
          );
        case 'Tf':
          font = fonts[operands[operands.length - 2].substring(1)] ?? const {};
          size = double.parse(operands.last);
        case 'Tj' || 'TJ':
          final text = RegExp(
            '<[0-9A-Fa-f]*>',
          ).allMatches(operands.last).map((m) => decode(m[0]!)).join();
          words.add((
            text: text,
            mode: state.mode,
            depth: saved.length,
            size: size,
            fill: state.fill,
            stroke: state.stroke,
            width: state.width,
          ));
        default:
          operands.add(token);
          continue;
      }
      operands.clear();
    }
    // Lo que se guardó sin reponer deja el estado del dibujo —el modo, el
    // trazo— puesto para lo que el lector dibuje después.
    if (saved.isNotEmpty) {
      throw StateError(
        '${saved.length} q sin su Q en la página ${pages.length}',
      );
    }
    pages.add(words);
  }
  return pages;
}
