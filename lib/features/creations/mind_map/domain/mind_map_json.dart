import 'dart:convert';

import 'package:sinapsis/features/creations/domain/services/structured_json.dart';
import 'package:sinapsis/features/creations/mind_map/domain/mind_map.dart';

/// Los topes de un mapa mental: lo que no entra se corta. Generosos —un mapa
/// de estudio rara vez pasa de cien ideas—, pero ponen un límite a lo que una
/// IA desbocada puede devolver y a lo que la pantalla tiene que dibujar.
abstract final class MindMapLimits {
  /// Ideas en total, la raíz incluida. Si hay más, se quedan los niveles de
  /// arriba enteros y se cortan las hojas más hondas.
  static const int nodes = 400;

  /// Niveles, la raíz incluida.
  static const int depth = 7;

  /// Ramas de una misma idea.
  static const int children = 24;

  static const int title = 140;
  static const int label = 120;
  static const int note = 320;
  static const int quote = 320;
}

/// El JSON de un mapa mental, en los dos sentidos (F43, decisión G).
///
/// [read] lee con tolerancia lo que devuelve la IA —y [decode], lo
/// guardado—:
///
/// - el árbol bajo `root` (o `raíz`, `central`, `mapa`…), o la raíz
///   directamente, o una lista de ramas;
/// - las claves en camelCase, snake_case o castellano: `label`, `text`,
///   `nombre`, `idea`…; `children`, `ramas`, `hijos`, `subtemas`…;
/// - una rama escrita como texto suelto (una hoja), o como `{"Idea": [...]}`;
/// - la fuente como título, como número (la primera fuente es la 1) o como
///   objeto con su pasaje; con una sola fuente en el material, todas las
///   ideas son de ella;
/// - dos ramas hermanas con el mismo nombre se unen en una, con lo de las
///   dos; una idea sin nombre deja sus ramas a la de arriba.
///
/// [encode] escribe la forma canónica, la que se guarda en «Lo creado» y la
/// que describe `mindMapSchemaPrompt`.
abstract final class MindMapJson {
  /// El mapa de [source] —un `Map`, una lista o el texto que devolvió la
  /// IA—. [sources] son los documentos del material (id → título): con ellos
  /// se reconoce de qué documento sale cada idea.
  ///
  /// Lanza [FormatException] con un motivo corto —el que se le dice a la IA
  /// al pedirle que lo corrija— si no hay ninguna idea con nombre o, salvo
  /// con [partial], si la raíz no tiene ramas: un borrador de una parte
  /// puede ser una sola rama, el mapa final no.
  static MindMap read(
    Object? source, {
    Map<String, String> sources = const {},
    bool partial = false,
  }) {
    final json = source is String ? extractJsonValue(source) : source;
    final reader = _Reader(sources);
    final (title, root) = reader.tree(json);
    if (root == null || root.label.isEmpty && root.children.isEmpty) {
      throw const FormatException(
        'No hay ninguna idea con nombre: falta "root" con su "label".',
      );
    }
    var top = root;
    if (top.label.isEmpty) {
      // Una lista de ramas sin raíz, o una raíz sin nombre: la raíz es el
      // título; sin título, con una sola rama, esa es la raíz.
      if (title.isNotEmpty) {
        top = _Draft(
          title,
          note: top.note,
          source: top.source,
          children: top.children,
        );
      } else if (top.children.length == 1) {
        top = top.children.single;
      } else if (!partial) {
        throw const FormatException(
          'La raíz no tiene nombre: falta su "label".',
        );
      }
    }
    if (!partial && top.children.isEmpty) {
      throw const FormatException(
        'El mapa no tiene ramas: la raíz necesita "children".',
      );
    }
    final kept = _keep(top);
    final node = _build(top, '0', kept, reader.only);
    final shownTitle = _clamp(
      title.isEmpty ? node.label : title,
      MindMapLimits.title,
    );
    return MindMap(title: shownTitle, root: node);
  }

  /// Como [read], o `null` si ahí no hay un mapa que leer.
  static MindMap? tryDecode(
    Object? source, {
    Map<String, String> sources = const {},
    bool partial = false,
  }) {
    try {
      return read(source, sources: sources, partial: partial);
    } on FormatException {
      return null;
    }
  }

  /// Lo guardado en una creación: como [tryDecode], pero sin mapa devuelve
  /// uno vacío —una raíz sin ramas— en vez de `null`.
  static MindMap decode(Object? source) =>
      tryDecode(source, partial: true) ??
      const MindMap(
        title: '',
        root: MindMapNode(id: '0', label: ''),
      );

  static Map<String, Object?> encode(MindMap map) => {
    'title': map.title,
    'root': encodeNode(map.root),
  };

  static String encodeString(MindMap map) => jsonEncode(encode(map));

  static Map<String, Object?> encodeNode(MindMapNode node) {
    final source = node.source;
    return {
      'label': node.label,
      if (node.note != null) 'note': node.note,
      if (source?.documentId != null) 'document_id': source!.documentId,
      if (source?.documentTitle != null) 'source': source!.documentTitle,
      if (source?.quote != null) 'quote': source!.quote,
      if (node.children.isNotEmpty)
        'children': [for (final child in node.children) encodeNode(child)],
    };
  }

  /// Qué ideas entran en [MindMapLimits.nodes]: las de arriba primero, nivel
  /// por nivel —así no se pierde una rama entera de las primeras por haber
  /// muchas hojas hondas en otra—.
  static Set<_Draft> _keep(_Draft root) {
    final kept = <_Draft>{};
    var level = [root];
    while (level.isNotEmpty && kept.length < MindMapLimits.nodes) {
      final next = <_Draft>[];
      for (final draft in level) {
        if (kept.length >= MindMapLimits.nodes) break;
        kept.add(draft);
        next.addAll(draft.children);
      }
      level = next;
    }
    return kept;
  }

  static MindMapNode _build(
    _Draft draft,
    String id,
    Set<_Draft> kept,
    MindMapSource? only,
  ) {
    final children = [
      for (final child in draft.children)
        if (kept.contains(child)) child,
    ];
    var source = draft.source ?? only;
    if (only != null && source != null && source.documentId == null) {
      // Con una sola fuente, el pasaje es de ella aunque la IA no la nombre.
      source = MindMapSource(
        documentId: only.documentId,
        documentTitle: only.documentTitle,
        quote: source.quote,
      );
    }
    return MindMapNode(
      id: id,
      label: draft.label,
      note: draft.note,
      source: source == null || source.isEmpty ? null : source,
      children: [
        for (final (i, child) in children.indexed)
          _build(child, '$id.$i', kept, only),
      ],
    );
  }
}

/// Una idea leída, antes de numerarla.
class _Draft {
  _Draft(this.label, {this.note, this.source, List<_Draft>? children})
    : children = children ?? [];

  final String label;
  String? note;
  MindMapSource? source;
  final List<_Draft> children;
}

class _Reader {
  _Reader(this.sources)
    : _byTitle = {
        for (final entry in sources.entries) _fold(entry.value): entry.key,
      },
      _order = sources.keys.toList();

  /// Los documentos del material: id → título.
  final Map<String, String> sources;
  final Map<String, String> _byTitle;
  final List<String> _order;

  /// Con un solo documento en el material, de él sale todo.
  MindMapSource? get only => sources.length == 1
      ? MindMapSource(
          documentId: sources.keys.single,
          documentTitle: sources.values.single,
        )
      : null;

  /// El título y la raíz de lo que llegó.
  (String, _Draft?) tree(Object? json) {
    if (json is List) {
      return ('', _Draft('', children: _children(json, 1)));
    }
    if (json is! Map) {
      return (
        '',
        json is String && json.trim().isNotEmpty ? _leaf(json) : null,
      );
    }
    final map = _normalize(json);
    final title = _text(map['title'], MindMapLimits.title);
    final rootValue = map['root'];
    if (rootValue is Map) {
      return (title, _node(rootValue, 0));
    }
    if (rootValue is List) {
      return (title, _Draft('', children: _children(rootValue, 1)));
    }
    if (rootValue is String && rootValue.trim().isNotEmpty) {
      // `{"root": "Éxodo", "children": [...]}`: el nombre arriba y las ramas
      // al lado.
      final children = map['children'];
      return (
        title,
        _Draft(
          _text(rootValue, MindMapLimits.label),
          children: _children(children, 1),
        ),
      );
    }
    // La raíz es el objeto mismo.
    final node = _node(json, 0);
    return (node?.label == title ? '' : title, node);
  }

  _Draft? _node(Map<Object?, Object?> raw, int depth) {
    final map = _normalize(raw);
    var label = _text(map['label'] ?? map['title'], MindMapLimits.label);
    var children = map['children'];
    if (label.isEmpty && children == null && map.length == 1) {
      // `{"Salida de Egipto": [...]}`: el nombre es la clave.
      final entry = raw.entries.single;
      final value = entry.value;
      if (value is List || value is Map) {
        label = _text(entry.key, MindMapLimits.label);
        children = value;
      }
    }
    final draft = _Draft(
      label,
      note: _textOrNull(map['note'], MindMapLimits.note),
      source: _source(map),
      children: _children(children, depth + 1),
    );
    if (draft.label.isEmpty && draft.children.isEmpty) return null;
    return draft;
  }

  _Draft _leaf(String text) => _Draft(_text(text, MindMapLimits.label));

  /// Las ramas de una idea, ya unidas: las hermanas con el mismo nombre se
  /// juntan y las sin nombre dejan las suyas acá.
  List<_Draft> _children(Object? raw, int depth) {
    if (depth >= MindMapLimits.depth || raw == null) return [];
    final items = <_Draft>[];
    void add(_Draft? draft) {
      if (draft == null) return;
      if (draft.label.isEmpty) {
        draft.children.forEach(add);
        return;
      }
      final folded = _fold(draft.label);
      for (final sibling in items) {
        if (_fold(sibling.label) == folded) {
          _absorb(sibling, draft);
          return;
        }
      }
      items.add(draft);
    }

    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          add(_node(item, depth));
        } else if (item is String || item is num) {
          final text = item.toString().trim();
          if (text.isNotEmpty) add(_leaf(text));
        } else if (item is List) {
          // Una lista dentro de la lista: ramas sueltas del mismo nivel.
          _children(item, depth).forEach(add);
        }
      }
    } else if (raw is Map) {
      final map = _normalize(raw);
      if (map.containsKey('label') || map.containsKey('children')) {
        // Una sola rama escrita como objeto.
        add(_node(raw, depth));
      } else {
        // `{"Idea": [...], "Otra": "..."}`: cada clave, una rama.
        for (final entry in raw.entries) {
          final label = _text(entry.key, MindMapLimits.label);
          final value = entry.value;
          if (value is Map) {
            // `{"Idea": {"note": …, "children": […]}}`: lo de adentro es la
            // idea misma; si trae su propio nombre, es una rama de ella.
            final node = _node(value, depth);
            if (node == null) {
              add(_Draft(label));
            } else if (node.label.isEmpty ||
                _fold(node.label) == _fold(label)) {
              add(
                _Draft(
                  label,
                  note: node.note,
                  source: node.source,
                  children: node.children,
                ),
              );
            } else {
              add(_Draft(label, children: [node]));
            }
          } else if (value is List) {
            add(_Draft(label, children: _children(value, depth + 1)));
          } else if (value is String && value.trim().isNotEmpty) {
            add(_Draft(label, note: _textOrNull(value, MindMapLimits.note)));
          } else {
            add(_Draft(label));
          }
        }
      }
    } else if (raw is String && raw.trim().isNotEmpty) {
      add(_leaf(raw));
    }
    return items.length > MindMapLimits.children
        ? items.sublist(0, MindMapLimits.children)
        : items;
  }

  /// Lo de [from] pasa a [into], su hermana con el mismo nombre.
  void _absorb(_Draft into, _Draft from) {
    into
      ..note ??= from.note
      ..source ??= from.source;
    final folded = {for (final c in into.children) _fold(c.label): c};
    for (final child in from.children) {
      final twin = folded[_fold(child.label)];
      if (twin != null) {
        _absorb(twin, child);
      } else {
        into.children.add(child);
        folded[_fold(child.label)] = child;
      }
    }
  }

  MindMapSource? _source(Map<String, Object?> map) {
    final raw = map['source'];
    String? title;
    var id = map['documentid'] is String
        ? (map['documentid']! as String).trim()
        : null;
    var quote = _textOrNull(map['quote'], MindMapLimits.quote);
    if (raw is String) {
      title = raw.trim();
    } else if (raw is num) {
      final index = raw.round() - 1;
      if (index >= 0 && index < _order.length) id = _order[index];
    } else if (raw is Map) {
      final inner = _normalize(raw);
      final name = inner['title'] ?? inner['label'];
      if (name is String) title = name.trim();
      if (inner['documentid'] is String) {
        id = (inner['documentid']! as String).trim();
      }
      quote ??= _textOrNull(inner['quote'], MindMapLimits.quote);
    }
    if (title != null && title.isEmpty) title = null;
    if (id != null &&
        (id.isEmpty || sources.isNotEmpty && !sources.containsKey(id))) {
      id = null;
    }
    id ??= title == null ? null : _match(title);
    if (id != null && sources.containsKey(id)) title = sources[id];
    final source = MindMapSource(
      documentId: id,
      documentTitle: title,
      quote: quote,
    );
    return source.isEmpty ? null : source;
  }

  /// El documento cuyo título es [title]: igual sin tildes ni mayúsculas, o,
  /// si no, el único que lo contiene o está contenido en él.
  String? _match(String title) {
    final folded = _fold(title);
    if (folded.isEmpty) return null;
    final exact = _byTitle[folded];
    if (exact != null) return exact;
    final candidates = [
      for (final entry in _byTitle.entries)
        if (entry.key.isNotEmpty &&
            (entry.key.contains(folded) || folded.contains(entry.key)))
          entry.value,
    ];
    return candidates.length == 1 ? candidates.single : null;
  }

  /// Las claves con su nombre canónico.
  static Map<String, Object?> _normalize(Map<Object?, Object?> raw) {
    final out = <String, Object?>{};
    for (final entry in raw.entries) {
      final folded = _foldKey(entry.key.toString());
      final key = _aliases[folded] ?? folded;
      out.putIfAbsent(key, () => entry.value);
    }
    return out;
  }

  static const _aliases = <String, String>{
    // La raíz.
    'raiz': 'root',
    'central': 'root',
    'centraltopic': 'root',
    'centralidea': 'root',
    'centro': 'root',
    'temacentral': 'root',
    'ideacentral': 'root',
    'mindmap': 'root',
    'mapa': 'root',
    'map': 'root',
    'tree': 'root',
    'arbol': 'root',
    // El título.
    'titulo': 'title',
    'heading': 'title',
    'name': 'label',
    'nombre': 'label',
    'text': 'label',
    'texto': 'label',
    'topic': 'label',
    'tema': 'label',
    'idea': 'label',
    'concept': 'label',
    'concepto': 'label',
    'etiqueta': 'label',
    'node': 'label',
    'nodo': 'label',
    // Las ramas.
    'nodes': 'children',
    'nodos': 'children',
    'branches': 'children',
    'ramas': 'children',
    'hijos': 'children',
    'subnodes': 'children',
    'subnodos': 'children',
    'subtopics': 'children',
    'subtemas': 'children',
    'subideas': 'children',
    'subramas': 'children',
    'items': 'children',
    'ideas': 'children',
    'child': 'children',
    'kids': 'children',
    // La nota.
    'description': 'note',
    'descripcion': 'note',
    'detail': 'note',
    'details': 'note',
    'detalle': 'note',
    'summary': 'note',
    'resumen': 'note',
    'explanation': 'note',
    'explicacion': 'note',
    'nota': 'note',
    // La fuente.
    'document': 'source',
    'documento': 'source',
    'doc': 'source',
    'from': 'source',
    'fuente': 'source',
    'origen': 'source',
    'sourcetitle': 'source',
    'docid': 'documentid',
    'sourceid': 'documentid',
    // El pasaje.
    'passage': 'quote',
    'excerpt': 'quote',
    'citation': 'quote',
    'evidence': 'quote',
    'cita': 'quote',
    'pasaje': 'quote',
    'fragmento': 'quote',
    'extracto': 'quote',
  };

  static String _foldKey(String key) =>
      _fold(key).replaceAll(RegExp('[^a-z0-9]'), '');
}

/// [text] para comparar: sin mayúsculas, sin tildes, sin comillas y con los
/// espacios de a uno.
String _fold(String text) => text
    .toLowerCase()
    .replaceAll(RegExp('[áàâä]'), 'a')
    .replaceAll(RegExp('[éèêë]'), 'e')
    .replaceAll(RegExp('[íìîï]'), 'i')
    .replaceAll(RegExp('[óòôö]'), 'o')
    .replaceAll(RegExp('[úùûü]'), 'u')
    .replaceAll('ñ', 'n')
    .replaceAll(RegExp('[«»"“”‘’\']'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _text(Object? raw, int limit) {
  if (raw is! String && raw is! num) return '';
  final text = raw.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  return _clamp(text, limit);
}

String? _textOrNull(Object? raw, int limit) {
  final text = _text(raw, limit);
  return text.isEmpty ? null : text;
}

/// [text] cortado en [limit] caracteres, en la última palabra entera y con
/// «…».
String _clamp(String text, int limit) {
  if (text.length <= limit) return text;
  final cut = text.substring(0, limit - 1);
  final space = cut.lastIndexOf(' ');
  final head = space > limit * 0.6 ? cut.substring(0, space) : cut;
  return '${head.replaceFirst(RegExp(r'[\s,;:.—-]+$'), '')}…';
}
