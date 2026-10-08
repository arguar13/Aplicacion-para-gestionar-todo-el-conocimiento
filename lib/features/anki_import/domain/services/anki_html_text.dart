import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:sinapsis/features/anki_import/domain/entities/anki_media_ref.dart';

/// El texto de un campo de Anki, sin HTML, y los medios que referenciaba.
class AnkiText {
  const AnkiText(this.text, this.media);

  /// Texto plano: `<br>`, `<div>`, `<p>`, `<li>` hechos saltos de línea
  /// (las listas con `- `), las entidades (`&nbsp;`, `&amp;`, `&#233;`)
  /// resueltas, y la negrita y la cursiva como Markdown (`**x**`, `*x*`).
  final String text;

  /// Los medios, en el orden en que aparecían, sin repetir.
  final List<AnkiMediaRef> media;
}

final _soundTag = RegExp(r'\[sound:([^\]]*)\]', caseSensitive: false);

const _blockTags = {
  'div', 'p', 'li', 'ul', 'ol', 'tr', 'table', 'blockquote', 'pre', //
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'hr', 'dl', 'dt', 'dd', 'section',
  'article', 'header', 'footer', 'center',
};

const _audioExtensions = {
  'mp3', 'wav', 'ogg', 'oga', 'm4a', 'aac', 'flac', 'opus', 'wma', 'amr', //
  '3ga', 'spx',
};
const _videoExtensions = {'mp4', 'webm', 'mkv', 'mov', 'avi', 'ogv', 'm4v'};

/// Pasa el HTML de un campo de Anki a texto plano.
///
/// No lanza nunca: HTML roto (etiquetas sin cerrar, `<` sueltos) se lee como
/// lo leería un navegador. Los medios se sacan del texto y se devuelven en
/// [AnkiText.media]. Con [markdown] en `false` la negrita y la cursiva se
/// pierden (para el texto de los huecos, donde `**` dentro de `{{c1::...}}`
/// estorbaría).
AnkiText ankiHtmlToText(String html, {bool markdown = true}) {
  if (html.isEmpty) return const AnkiText('', []);

  final media = <AnkiMediaRef>[];
  void addMedia(String name, AnkiMediaKind kind) {
    final ref = AnkiMediaRef(name.trim(), kind);
    if (ref.name.isNotEmpty && !media.contains(ref)) media.add(ref);
  }

  // [sound:...] va en el texto, no en una etiqueta: se saca antes.
  final withoutSounds = html.replaceAllMapped(_soundTag, (match) {
    final name = match[1] ?? '';
    addMedia(name, _kindOfFile(name, fallback: AnkiMediaKind.audio));
    return '';
  });

  final fragment = html_parser.parseFragment(withoutSounds);
  final out = _Out();
  _walk(fragment.nodes, out, markdown: markdown, onMedia: addMedia);
  return AnkiText(_tidy(out.toString()), media);
}

AnkiMediaKind _kindOfFile(String name, {required AnkiMediaKind fallback}) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return fallback;
  final extension = name.substring(dot + 1).toLowerCase();
  if (_audioExtensions.contains(extension)) return AnkiMediaKind.audio;
  if (_videoExtensions.contains(extension)) return AnkiMediaKind.video;
  return fallback;
}

/// Un `StringBuffer` que sabe si lo último que se escribió fue un salto de
/// línea, sin volver a armar el texto entero cada vez.
class _Out {
  final _buffer = StringBuffer();
  bool _endsWithNewline = false;

  bool get isEmpty => _buffer.isEmpty;

  void write(String text) {
    if (text.isEmpty) return;
    _buffer.write(text);
    _endsWithNewline = text.endsWith('\n');
  }

  /// Un salto de línea, salvo que ya haya uno o que no haya nada todavía.
  void newline() {
    if (!isEmpty && !_endsWithNewline) write('\n');
  }

  @override
  String toString() => _buffer.toString();
}

void _walk(
  List<dom.Node> nodes,
  _Out out, {
  required bool markdown,
  required void Function(String name, AnkiMediaKind kind) onMedia,
}) {
  for (final node in nodes) {
    if (node is dom.Text) {
      out.write(node.text);
      continue;
    }
    if (node is! dom.Element) continue; // comentarios, etc.

    final tag = node.localName ?? '';
    switch (tag) {
      case 'script' || 'style' || 'head' || 'template':
        continue;
      case 'br':
        out.write('\n');
        continue;
      case 'img':
        final src = node.attributes['src'];
        if (src != null) onMedia(src, AnkiMediaKind.image);
        continue;
      case 'audio' || 'video' || 'source':
        final src = node.attributes['src'];
        if (src != null) {
          onMedia(
            src,
            _kindOfFile(
              src,
              fallback: tag == 'video'
                  ? AnkiMediaKind.video
                  : AnkiMediaKind.audio,
            ),
          );
        }
        if (tag == 'source') continue;
      default:
        break;
    }

    final emphasis = !markdown
        ? ''
        : switch (tag) {
            'b' || 'strong' => '**',
            'i' || 'em' => '*',
            _ => '',
          };
    final isBlock = _blockTags.contains(tag);
    if (isBlock) out.newline();
    if (tag == 'li') out.write('- ');

    // Lo de adentro se arma aparte para poder correr los espacios de los
    // bordes fuera de la marca: `**hola **` no es negrita en Markdown.
    final inner = _Out();
    _walk(node.nodes, inner, markdown: markdown, onMedia: onMedia);
    final innerText = inner.toString();
    if (emphasis.isEmpty) {
      out.write(innerText);
    } else {
      final core = innerText.trim();
      if (core.isEmpty) {
        out.write(innerText);
      } else {
        final lead = innerText.substring(0, innerText.indexOf(core));
        final trail = innerText.substring(lead.length + core.length);
        // Una marca de Markdown no cruza líneas: cada línea lleva la suya.
        final marked = core
            .split('\n')
            .map((line) => line.trim().isEmpty ? line : _wrap(line, emphasis))
            .join('\n');
        out.write('$lead$marked$trail');
      }
    }
    if (isBlock) out.newline();
  }
}

/// [line] con la marca [emphasis] a cada lado y los espacios de los bordes
/// fuera de ella (`**hola **` no es negrita en Markdown).
String _wrap(String line, String emphasis) {
  final core = line.trim();
  final lead = line.substring(0, line.indexOf(core));
  final trail = line.substring(lead.length + core.length);
  return '$lead$emphasis$core$emphasis$trail';
}

/// Espacios y saltos de línea en orden: nbsp a espacio, sin espacios al final
/// de línea, a lo sumo una línea en blanco seguida, y sin blancos en los
/// extremos.
String _tidy(String text) {
  final lines = text
      .replaceAll('\u00A0', ' ')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim());
  final joined = lines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return joined.trim();
}
