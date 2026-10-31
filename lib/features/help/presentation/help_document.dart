import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/chat/domain/services/chat_passages.dart'
    show foldForSearch;
import 'package:sinapsis/features/chat/presentation/widgets/chat_markdown_blocks.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';

/// Lo más corto que se busca: con una sola letra, casi todo coincide.
const kHelpSearchMinChars = 2;

/// Un documento de la Ayuda de Ajustes (F47, paso 7) —la guía de uso o las
/// novedades—, leído de su Markdown y partido en capítulos por sus títulos
/// de segundo nivel («##»).
///
/// Se lee con el mismo parser que las respuestas del chat
/// (`parseChatBlocks`), así que cada bloque guarda sus posiciones en [raw]:
/// lo encontrado al buscar se pinta en su lugar del texto, aunque la
/// pantalla no muestre los `#` ni los `**`.
///
/// - El título de primer nivel («#») es el del documento, [title].
/// - Lo que va entre él y el primer capítulo es la presentación, [preface].
/// - Los títulos de tercer nivel («###») son las secciones de cada capítulo,
///   y van al índice debajo de su capítulo; los de más abajo, no.
/// - Un capítulo que no es más que una lista de enlaces a títulos del mismo
///   documento es su índice escrito a mano —el «Índice» de la guía, con sus
///   `[…](#…)`—: se deja afuera, porque la app arma el suyo con los títulos
///   de verdad, que no se quedan viejos y sí se pueden tocar.
@immutable
class HelpDocument {
  HelpDocument._({
    required this.raw,
    required this.title,
    required this.preface,
    required this.chapters,
  });

  factory HelpDocument.parse(String raw) {
    final blocks = parseChatBlocks(raw);
    String? title;
    final preface = <ChatBlock>[];
    final chapters = <HelpChapter>[];

    // Los bloques de cada capítulo, empezando por su título.
    final groups = <List<ChatBlock>>[];
    for (final block in blocks) {
      final level = block.kind == ChatBlockKind.heading ? block.level : 0;
      if (level == 1 && title == null && groups.isEmpty && preface.isEmpty) {
        title = displayTextOf(raw, block.content);
      } else if (level == 2) {
        groups.add([block]);
      } else if (groups.isEmpty) {
        preface.add(block);
      } else {
        groups.last.add(block);
      }
    }

    for (final group in groups) {
      if (_isHandwrittenIndex(raw, group)) continue;
      final sections = <HelpSection>[
        for (var i = 1; i < group.length; i++)
          if (group[i].kind == ChatBlockKind.heading && group[i].level == 3)
            HelpSection(
              title: displayTextOf(raw, group[i].content),
              blockIndex: i,
            ),
      ];
      chapters.add(
        HelpChapter(
          index: chapters.length,
          title: displayTextOf(raw, group.first.content),
          blocks: List.unmodifiable(group),
          sections: List.unmodifiable(sections),
        ),
      );
    }

    return HelpDocument._(
      raw: raw,
      title: title,
      preface: List.unmodifiable(preface),
      chapters: List.unmodifiable(chapters),
    );
  }

  /// El Markdown entero, tal cual: de él salen todas las posiciones.
  final String raw;

  /// El título de primer nivel, si tiene uno.
  final String? title;

  /// Lo que va entre [title] y el primer capítulo.
  final List<ChatBlock> preface;

  final List<HelpChapter> chapters;

  /// Lo que se busca, armado la primera vez que se busca: cada tramo de
  /// texto de los capítulos, como se lee y ya plegado.
  late final List<_SearchUnit> _units = _buildUnits();

  /// Dónde aparece [query] en los capítulos, en orden: sin mayúsculas ni
  /// acentos —«busqueda» encuentra «Búsqueda»— y con los espacios y saltos
  /// de renglón como uno solo, porque la guía corta sus renglones a mano y
  /// una frase puede quedar partida en dos.
  ///
  /// Con menos de [kHelpSearchMinChars] letras no busca nada.
  List<HelpMatch> search(String query) {
    final needle = _collapse(foldForSearch(query)).trim();
    if (needle.length < kHelpSearchMinChars) return const [];

    final matches = <HelpMatch>[];
    for (final unit in _units) {
      var from = unit.folded.indexOf(needle);
      while (from >= 0) {
        final to = from + needle.length;
        final displayStart = unit.toDisplay[from];
        final displayEnd = unit.toDisplay[to - 1] + 1;
        matches.add(
          HelpMatch(
            chapter: unit.chapter,
            block: unit.block,
            start: unit.rawStart + unit.rendered.renderToRaw(displayStart),
            end:
                unit.rawStart +
                unit.rendered.renderToRaw(displayEnd, isEnd: true),
            snippet: _snippet(
              unit.rendered.displayText,
              displayStart,
              displayEnd,
            ),
          ),
        );
        from = unit.folded.indexOf(needle, to);
      }
    }
    return matches;
  }

  List<_SearchUnit> _buildUnits() {
    final units = <_SearchUnit>[];
    for (final chapter in chapters) {
      for (var b = 0; b < chapter.blocks.length; b++) {
        final block = chapter.blocks[b];
        final ranges = switch (block.kind) {
          ChatBlockKind.table => [for (final row in block.rows) ...row],
          ChatBlockKind.rule => const <ChatTextRange>[],
          _ => [block.content],
        };
        for (final range in ranges) {
          if (range.end <= range.start) continue;
          final text = raw.substring(range.start, range.end);
          final rendered = block.kind == ChatBlockKind.code
              ? RenderedMarkdown.plain(text)
              : RenderedMarkdown.parse(text);
          units.add(
            _SearchUnit.of(
              chapter: chapter.index,
              block: b,
              rawStart: range.start,
              rendered: rendered,
            ),
          );
        }
      }
    }
    return units;
  }
}

/// Un capítulo: su título («##») y lo que sigue hasta el próximo.
@immutable
class HelpChapter {
  const HelpChapter({
    required this.index,
    required this.title,
    required this.blocks,
    required this.sections,
  });

  /// Su lugar entre los capítulos, desde 0.
  final int index;

  /// Como se lee, sin marcado.
  final String title;

  /// Sus bloques, el primero su título.
  final List<ChatBlock> blocks;

  /// Sus títulos de tercer nivel, en orden.
  final List<HelpSection> sections;
}

/// Una sección de un capítulo: su título («###») y en qué bloque está.
@immutable
class HelpSection {
  const HelpSection({required this.title, required this.blockIndex});

  final String title;

  /// El índice de su título en [HelpChapter.blocks].
  final int blockIndex;
}

/// Un lugar donde está lo buscado.
@immutable
class HelpMatch {
  const HelpMatch({
    required this.chapter,
    required this.block,
    required this.start,
    required this.end,
    required this.snippet,
  });

  /// En qué capítulo, y en qué bloque de él ([HelpChapter.blocks]).
  final int chapter;
  final int block;

  /// `[start, end)` en [HelpDocument.raw].
  final int start;
  final int end;

  /// El renglón donde está, para la lista de resultados.
  final HelpSnippet snippet;

  @override
  bool operator ==(Object other) =>
      other is HelpMatch &&
      other.chapter == chapter &&
      other.block == block &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(chapter, block, start, end);
}

/// Un pedazo de texto alrededor de lo encontrado: lo de antes, lo
/// encontrado y lo de después, cada uno en un solo renglón.
@immutable
class HelpSnippet {
  const HelpSnippet(this.before, this.match, this.after);

  final String before;
  final String match;
  final String after;
}

/// El texto de [range] de [raw] como se lee: sin `**`, sin enlaces con su
/// dirección y en un solo renglón.
String displayTextOf(String raw, ChatTextRange range) => _collapse(
  RenderedMarkdown.parse(raw.substring(range.start, range.end)).displayText,
).trim();

/// Si [group] —un capítulo, con su título— es una lista de enlaces a títulos
/// del mismo documento y nada más (un separador, como el `---` que cierra el
/// índice de la guía, no cuenta).
bool _isHandwrittenIndex(String raw, List<ChatBlock> group) {
  var links = 0;
  for (final block in group.skip(1)) {
    if (block.kind == ChatBlockKind.rule) continue;
    if (block.kind != ChatBlockKind.listItem) return false;
    final content = raw.substring(block.content.start, block.content.end);
    if (!_anchorLink.hasMatch(content.trim())) return false;
    links++;
  }
  return links > 0;
}

final _anchorLink = RegExp(r'^\[[^\]\n]+\]\(#[^)\s]+\)$');

final _spaces = RegExp(r'\s+');

String _collapse(String text) => text.replaceAll(_spaces, ' ');

/// Cuántos caracteres de contexto lleva un resultado, antes y después.
const _snippetBefore = 40;
const _snippetAfter = 90;

HelpSnippet _snippet(String display, int start, int end) {
  var from = (start - _snippetBefore).clamp(0, display.length);
  var to = (end + _snippetAfter).clamp(0, display.length);
  // Sin cortar palabras a la mitad.
  while (from > 0 && from < start && display[from - 1].trim().isNotEmpty) {
    from++;
  }
  while (to < display.length && to > end && display[to].trim().isNotEmpty) {
    to--;
  }
  final before = _collapse(display.substring(from, start)).trimLeft();
  final after = _collapse(display.substring(end, to)).trimRight();
  return HelpSnippet(
    '${from > 0 ? '…' : ''}$before',
    _collapse(display.substring(start, end)),
    '$after${to < display.length ? '…' : ''}',
  );
}

/// Un tramo de texto donde se busca: un párrafo, un renglón de lista, un
/// título, una celda.
class _SearchUnit {
  _SearchUnit._({
    required this.chapter,
    required this.block,
    required this.rawStart,
    required this.rendered,
    required this.folded,
    required this.toDisplay,
  });

  factory _SearchUnit.of({
    required int chapter,
    required int block,
    required int rawStart,
    required RenderedMarkdown rendered,
  }) {
    // `foldForSearch` no cambia el largo: cada letra plegada está donde
    // estaba. Después, cada tramo de espacios queda en uno solo, y
    // [toDisplay] dice de qué letra de lo que se ve sale cada una.
    final display = rendered.displayText;
    var plain = foldForSearch(display);
    if (plain.length != display.length) {
      // Una letra que en minúscula ocupa dos —la «İ» turca— correría todo lo
      // que sigue: en ese caso se pliega de a una, quedándose con la primera.
      plain = [
        for (var i = 0; i < display.length; i++) foldForSearch(display[i])[0],
      ].join();
    }
    final folded = StringBuffer();
    final toDisplay = <int>[];
    var inSpace = false;
    for (var i = 0; i < plain.length; i++) {
      final isSpace = plain[i].trim().isEmpty;
      if (isSpace && inSpace) continue;
      inSpace = isSpace;
      folded.write(isSpace ? ' ' : plain[i]);
      toDisplay.add(i);
    }
    return _SearchUnit._(
      chapter: chapter,
      block: block,
      rawStart: rawStart,
      rendered: rendered,
      folded: folded.toString(),
      toDisplay: Int32List.fromList(toDisplay),
    );
  }

  final int chapter;
  final int block;

  /// Dónde empieza en [HelpDocument.raw].
  final int rawStart;
  final RenderedMarkdown rendered;

  /// Lo que se ve, en minúsculas, sin acentos y con un espacio por tramo.
  final String folded;

  /// De qué posición de lo que se ve sale cada letra de [folded].
  final Int32List toDisplay;
}
