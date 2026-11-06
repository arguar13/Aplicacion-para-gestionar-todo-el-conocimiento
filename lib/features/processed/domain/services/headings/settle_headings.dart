import 'package:sinapsis/features/processed/domain/entities/processed_heading.dart';

/// Lo que se guarda de lo que devolvió `HeadingsExtractor` para un texto de
/// [textLength] caracteres (F46, paso 2): lo mismo, en el mismo orden, con lo
/// que la base exige cumplido aunque el puerto no lo cumpla —sus `assert` no
/// corren en la app—.
///
/// - el título, con los espacios juntos y sin los de los bordes; un capítulo
///   que queda en blanco no es un capítulo y no entra. «Texto completo» va
///   siempre sin título;
/// - los niveles, corridos para que el más alto sea el 1 —si ya lo eran,
///   quedan igual—;
/// - el tramo y su página del texto, juntos y solo si caen adentro del texto;
///   si no, ninguno de los tres —el título queda, sin lugar—;
/// - la página del PDF, solo desde 1;
/// - el orden, de 0 en adelante sin huecos: el de la lista.
///
/// Es el borde entre el puerto y la base: lo que pasa por acá no rompe nunca
/// una restricción de `processed_headings`, y así un título raro no tumba el
/// guardado de un texto.
List<ProcessedHeading> settleHeadings(
  List<ProcessedHeading> headings, {
  required int textLength,
}) {
  final kept = [
    for (final heading in headings)
      if (heading.origin == ProcessedHeadingOrigin.wholeText)
        (heading, '')
      else if (collapseSpaces(heading.title) case final title
          when title.isNotEmpty)
        (heading, title),
  ];
  if (kept.isEmpty) return const [];
  final top = kept
      .map((entry) => entry.$1.level)
      .reduce((a, b) => a < b ? a : b);
  return [
    for (final (order, (heading, title)) in kept.indexed)
      _settled(
        heading,
        order: order,
        title: title,
        level: heading.level - top + 1,
        textLength: textLength,
      ),
  ];
}

ProcessedHeading _settled(
  ProcessedHeading heading, {
  required int order,
  required String title,
  required int level,
  required int textLength,
}) {
  final start = heading.start;
  final end = heading.end;
  final textPage = heading.textPage;
  final placed =
      start != null &&
      end != null &&
      textPage != null &&
      start >= 0 &&
      end >= start &&
      end <= textLength &&
      textPage >= 1;
  final pdfPage = heading.pdfPage;
  return ProcessedHeading(
    order: order,
    level: level,
    title: title,
    origin: heading.origin,
    start: placed ? start : null,
    end: placed ? end : null,
    textPage: placed ? textPage : null,
    pdfPage: pdfPage != null && pdfPage >= 1 ? pdfPage : null,
  );
}

/// [text] con cada tramo de espacios —también saltos de línea y tabulaciones—
/// convertido en uno solo, y sin los de los bordes: como se lee un título.
String collapseSpaces(String text) =>
    text.replaceAll(RegExp(r'\s+'), ' ').trim();
