/// Las plantillas de tarjeta de Anki (`qfmt`/`afmt` de un modelo de nota),
/// lo justo para sacar de una nota lo que se ve del frente y del dorso:
///
/// - `{{Campo}}`, con filtros delante (`{{text:Campo}}`, `{{hint:Campo}}`,
///   `{{type:Campo}}`, `{{cloze:Campo}}`): el valor del campo, salvo `hint`
///   (un enlace «mostrar», que sin pantalla no tiene qué decir) y `type`
///   (la caja donde se escribe: en el frente no se ve, en el dorso es la
///   respuesta). Cualquier otro filtro (`furigana:`, `kana:`…) deja el valor.
/// - `{{FrontSide}}`, `{{Tags}}`, `{{Deck}}`, `{{Subdeck}}`, `{{Card}}`.
/// - Condicionales `{{#Campo}}…{{/Campo}}` y `{{^Campo}}…{{/Campo}}`, también
///   anidados. Un campo está vacío si solo tiene blancos o `<br>`/`<div>`
///   (como lo decide Anki).
/// - Comentarios `{{! … }}`.
///
/// No hay JavaScript ni CSS: es la salida en HTML, y para el texto se pasa
/// por `ankiHtmlToText`.
class AnkiTemplate {
  AnkiTemplate._(this._nodes);

  /// Lee [source]. Una etiqueta que no se cierra, o un `{{/Campo}}` de más,
  /// no lanza: lo que no se entiende se deja como texto.
  factory AnkiTemplate.parse(String source) {
    final root = _Section('', inverted: false);
    final stack = <_Section>[root];
    var cursor = 0;
    for (final match in _tag.allMatches(source)) {
      if (match.start > cursor) {
        stack.last.children.add(_Text(source.substring(cursor, match.start)));
      }
      cursor = match.end;
      final body = match[1]!.trim();

      if (body.startsWith('!')) continue; // comentario
      if (body.startsWith('#') || body.startsWith('^')) {
        final section = _Section(
          body.substring(1).trim(),
          inverted: body.startsWith('^'),
        );
        stack.last.children.add(section);
        stack.add(section);
      } else if (body.startsWith('/')) {
        final name = body.substring(1).trim();
        final open = stack.lastIndexWhere((s) => s.name == name);
        // Un cierre sin su apertura se ignora; uno que cierra una anterior
        // cierra también las que quedaron abiertas adentro.
        if (open > 0) stack.removeRange(open, stack.length);
      } else {
        stack.last.children.add(_Variable(body));
      }
    }
    if (cursor < source.length) {
      stack.last.children.add(_Text(source.substring(cursor)));
    }
    return AnkiTemplate._(root.children);
  }

  final List<_Node> _nodes;

  /// Cada etiqueta que la plantilla pide, con sus filtros: para saber, por
  /// ejemplo, si el frente tiene un `{{type:Campo}}` o un `{{cloze:Campo}}`.
  List<AnkiTemplateVariable> get variables {
    final out = <AnkiTemplateVariable>[];
    void collect(List<_Node> nodes) {
      for (final node in nodes) {
        switch (node) {
          case _Variable():
            out.add(AnkiTemplateVariable(node.field, node.filters));
          case _Section():
            collect(node.children);
          case _Text():
            break;
        }
      }
    }

    collect(_nodes);
    return out;
  }

  /// La plantilla en HTML. [fields] es nombre de campo → valor (HTML).
  /// [frontSide] es lo que reemplaza a `{{FrontSide}}`; [answerSide] dice si
  /// se arma el dorso (cambia lo que hace `{{type:Campo}}`); [special] son
  /// `Tags`, `Deck`, `Subdeck` y `Card`.
  ///
  /// [clozeFilter], si se da, se llama con el valor del campo para cada
  /// `{{cloze:Campo}}` y devuelve lo que se escribe en su lugar. Sin él, el
  /// campo se escribe tal cual.
  String render(
    Map<String, String> fields, {
    String frontSide = '',
    bool answerSide = false,
    Map<String, String> special = const {},
    String Function(String value)? clozeFilter,
  }) {
    final out = StringBuffer();
    void walk(List<_Node> nodes) {
      for (final node in nodes) {
        switch (node) {
          case _Text():
            out.write(node.text);
          case _Section():
            final empty = _isEmpty(fields[node.name]);
            if (node.inverted ? empty : !empty) walk(node.children);
          case _Variable():
            out.write(
              _valueOf(
                node,
                fields,
                frontSide: frontSide,
                answerSide: answerSide,
                special: special,
                clozeFilter: clozeFilter,
              ),
            );
        }
      }
    }

    walk(_nodes);
    return out.toString();
  }
}

/// Una etiqueta `{{filtro:filtro:Campo}}` de la plantilla.
class AnkiTemplateVariable {
  const AnkiTemplateVariable(this.field, this.filters);

  final String field;
  final List<String> filters;

  bool hasFilter(String filter) => filters.contains(filter);
}

final _tag = RegExp(r'\{\{(.*?)\}\}', dotAll: true);

/// Un campo vacío para Anki: nada, o solo blancos y `<br>`/`<div>`.
final _emptyField = RegExp(
  r'^(?:\s|</?(?:br|div)\s*/?>)*$',
  caseSensitive: false,
);

bool _isEmpty(String? value) => value == null || _emptyField.hasMatch(value);

String _valueOf(
  _Variable variable,
  Map<String, String> fields, {
  required String frontSide,
  required bool answerSide,
  required Map<String, String> special,
  required String Function(String value)? clozeFilter,
}) {
  final field = variable.field;
  if (variable.filters.isEmpty) {
    if (field == 'FrontSide') return frontSide;
    if (!fields.containsKey(field) && special.containsKey(field)) {
      return special[field]!;
    }
  }
  final value = fields[field] ?? special[field] ?? '';
  if (variable.filters.contains('hint')) return '';
  if (variable.filters.contains('type')) return answerSide ? value : '';
  if (variable.filters.contains('cloze')) {
    return clozeFilter == null ? value : clozeFilter(value);
  }
  return value;
}

sealed class _Node {}

class _Text extends _Node {
  _Text(this.text);
  final String text;
}

class _Variable extends _Node {
  _Variable(String body)
    : this._(body.split(':').map((p) => p.trim()).toList());

  _Variable._(List<String> parts)
    : field = parts.last,
      filters = parts.sublist(0, parts.length - 1);

  final String field;
  final List<String> filters;
}

class _Section extends _Node {
  _Section(this.name, {required this.inverted});
  final String name;
  final bool inverted;
  final children = <_Node>[];
}
