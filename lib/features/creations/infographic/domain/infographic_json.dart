import 'dart:convert';

import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_numbers.dart';

/// Los topes de cada campo: lo que no entra se corta en la última palabra
/// entera, con «…». Son generosos —el dibujo además achica la letra para
/// que entre—, pero ponen un límite a lo que una IA desbocada puede
/// devolver.
abstract final class InfographicLimits {
  static const int blocks = 14;
  static const int title = 120;
  static const int subtitle = 220;
  static const int kicker = 60;
  static const int takeaway = 220;
  static const int source = 160;
  static const int value = 18;
  static const int label = 140;
  static const int detail = 260;
  static const int point = 160;
  static const int points = 5;
  static const int quote = 360;
  static const int attribution = 120;
  static const int unit = 16;
  static const int data = 8;
  static const int prompt = 500;
  static const int reference = 1024;
  static const int icon = 40;
}

/// El JSON de una infografía, en los dos sentidos (F43, decisión G).
///
/// [tryDecode] lee con tolerancia lo que devuelve la IA —y lo guardado—:
/// acepta el JSON envuelto en ```json o con texto alrededor, las claves en
/// camelCase, snake_case o castellano, los bloques sueltos o agrupados en
/// secciones, el tipo de bloque escrito de varias maneras (o deducido de sus
/// campos si falta), los números como número o como texto («40 %»,
/// «3.000.000») y los datos de un gráfico como lista, como dos listas
/// paralelas o como un objeto. Nunca falla por un campo: falla solo si no hay
/// ningún bloque que leer.
///
/// [encode] escribe la forma canónica, la que se guarda en «Lo creado» y la
/// que describe `infographicJsonSchemaPrompt`.
abstract final class InfographicJson {
  /// La infografía de [source] —un `Map`, una lista de bloques o el texto que
  /// devolvió la IA—, o null si ahí no hay ningún bloque legible (es lo que
  /// hace que se le pida a la IA que lo corrija).
  static Infographic? tryDecode(Object? source) {
    final json = source is String ? _parseText(source) : source;
    final Map<String, Object?> sheet;
    if (json is List) {
      sheet = {'blocks': json};
    } else if (json is Map) {
      sheet = _normalizeKeys(json);
    } else {
      return null;
    }
    final blocks = <InfographicBlock>[];
    for (final raw in _rawBlocks(sheet)) {
      final block = decodeBlock(raw);
      if (block != null) blocks.add(block);
      if (blocks.length == InfographicLimits.blocks) break;
    }
    if (blocks.isEmpty) return null;
    final title = _text(sheet['title'], InfographicLimits.title);
    final common = _Common.of(sheet);
    return Infographic(
      title: title.isNotEmpty
          ? title
          : _clamp(blocks.first.headline, InfographicLimits.title),
      subtitle: _text(sheet['subtitle'], InfographicLimits.subtitle),
      kicker: _text(sheet['kicker'], InfographicLimits.kicker),
      blocks: _withLevels(blocks, _hasLevels(_rawBlocks(sheet))),
      takeaway: _text(sheet['takeaway'], InfographicLimits.takeaway),
      source: _text(sheet['source'], InfographicLimits.source),
      styleHint: _hint(sheet['style']),
      compositionHint: _hint(sheet['composition']),
      illustrationPrompt: common.prompt,
      illustrationRef: common.reference,
    );
  }

  /// Como [tryDecode], pero sin ningún bloque devuelve una infografía vacía
  /// en vez de null: para leer lo guardado, que ya pasó por acá una vez.
  static Infographic decode(Object? source) =>
      tryDecode(source) ?? const Infographic(title: '');

  static Map<String, Object?> encode(Infographic sheet) => {
    'title': sheet.title,
    if (sheet.subtitle.isNotEmpty) 'subtitle': sheet.subtitle,
    if (sheet.kicker.isNotEmpty) 'kicker': sheet.kicker,
    if (sheet.styleHint != null) 'style_hint': sheet.styleHint,
    if (sheet.compositionHint != null)
      'composition_hint': sheet.compositionHint,
    if (sheet.illustrationPrompt != null)
      'illustration_prompt': sheet.illustrationPrompt,
    if (sheet.illustrationRef != null)
      'illustration_ref': sheet.illustrationRef,
    'blocks': [for (final block in sheet.blocks) encodeBlock(block)],
    if (sheet.takeaway.isNotEmpty) 'takeaway': sheet.takeaway,
    if (sheet.source.isNotEmpty) 'source': sheet.source,
  };

  static String encodeString(Infographic sheet) => jsonEncode(encode(sheet));

  /// Un bloque, o null si no trae nada de texto.
  static InfographicBlock? decodeBlock(Object? raw) {
    if (raw is String) {
      final title = _text(raw, InfographicLimits.label);
      return title.isEmpty ? null : InfographicBlock.fact(title: title);
    }
    if (raw is! Map) return null;
    final json = _normalizeKeys(raw);
    final common = _Common.of(json);
    final kind = _kind(json['type']) ?? _guessKind(json);
    final block = switch (kind) {
      InfographicBlockKind.stat => _stat(json, common),
      InfographicBlockKind.fact => null,
      InfographicBlockKind.step => _titled(
        json,
        common,
        InfographicBlockKind.step,
      ),
      InfographicBlockKind.comparison => _comparison(json, common),
      InfographicBlockKind.event => _event(json, common),
      InfographicBlockKind.concept => _titled(
        json,
        common,
        InfographicBlockKind.concept,
      ),
      InfographicBlockKind.quote => _quote(json, common),
      InfographicBlockKind.chart => _chart(json, common),
    };
    // El hecho es también la red de un tipo al que le falta lo suyo: se
    // juntan los textos que haya.
    return block ?? _fact(json, common);
  }

  static Map<String, Object?> encodeBlock(InfographicBlock block) {
    final json = <String, Object?>{'type': block.kind.jsonName};
    void put(String key, String? value) {
      if (value != null && value.isNotEmpty) json[key] = value;
    }

    Map<String, Object?> side(InfographicSide s) => {
      if (s.heading.isNotEmpty) 'heading': s.heading,
      'points': s.points,
      if (s.icon != null) 'icon': s.icon,
    };

    switch (block) {
      case StatBlock(:final value, :final label, :final detail, :final icon):
        put('value', value);
        put('label', label);
        put('detail', detail);
        put('icon', icon);
      case FactBlock(:final title, :final detail, :final icon) ||
          StepBlock(:final title, :final detail, :final icon) ||
          ConceptBlock(:final title, :final detail, :final icon):
        put('title', title);
        put('detail', detail);
        put('icon', icon);
      case ComparisonBlock(
        :final title,
        :final left,
        :final right,
        :final conclusion,
      ):
        put('title', title);
        json['left'] = side(left);
        json['right'] = side(right);
        put('conclusion', conclusion);
      case EventBlock(:final date, :final title, :final detail, :final icon):
        put('date', date);
        put('title', title);
        put('detail', detail);
        put('icon', icon);
      case QuoteBlock(:final quote, :final author, :final source):
        put('quote', quote);
        put('author', author);
        put('source', source);
      case ChartBlock(
        :final title,
        :final chartKind,
        :final data,
        :final unit,
        :final total,
        :final detail,
      ):
        put('title', title);
        put('chart', chartKind?.jsonName);
        json['data'] = [
          for (final d in data)
            {
              'label': d.label,
              'value': d.value == d.value.roundToDouble()
                  ? d.value.toInt()
                  : d.value,
              if (d.display.isNotEmpty) 'display': d.display,
            },
        ];
        put('unit', unit);
        if (total != null) {
          json['total'] = total == total.roundToDouble()
              ? total.toInt()
              : total;
        }
        put('detail', detail);
    }
    json['level'] = block.level.value;
    put('illustration_prompt', block.illustrationPrompt);
    put('illustration_ref', block.illustrationRef);
    return json;
  }

  // ---------------------------------------------------------------------
  // Cada tipo. Devuelven null si les falta lo que los define, y entonces el
  // bloque se lee como un hecho.

  static InfographicBlock? _stat(Map<String, Object?> j, _Common c) {
    var value = _text(j['value'], InfographicLimits.label);
    var label = _text(j['label'] ?? j['title'], InfographicLimits.label);
    if (value.isEmpty) return null;
    // «40 años de travesía» en el valor: la cifra y su unidad quedan en el
    // valor, lo demás pasa al rótulo.
    if (value.length > InfographicLimits.value && label.isEmpty) {
      final match = RegExp(r'^(\S+(?:\s\S+)?)\s+(.+)$').firstMatch(value);
      if (match != null) {
        value = match.group(1)!;
        label = match.group(2)!;
      }
    }
    return InfographicBlock.stat(
      value: _clamp(value, InfographicLimits.value),
      label: label,
      detail: _text(j['detail'], InfographicLimits.detail),
      icon: c.icon,
      level: c.level,
      illustrationPrompt: c.prompt,
      illustrationRef: c.reference,
    );
  }

  static InfographicBlock? _fact(Map<String, Object?> j, _Common c) {
    var title = _text(j['title'] ?? j['label'], InfographicLimits.label);
    var detail = _text(j['detail'], InfographicLimits.detail);
    if (title.isEmpty) {
      // Lo que traiga otro tipo, para no perderlo.
      final loose = [
        for (final key in ['value', 'quote', 'date', 'conclusion'])
          _text(j[key], InfographicLimits.label),
        ..._strings(j['points'], InfographicLimits.point),
      ].where((t) => t.isNotEmpty).toList();
      if (loose.isNotEmpty) {
        title = loose.first;
      } else {
        title = _clamp(detail, InfographicLimits.label);
        detail = '';
      }
    }
    if (title.isEmpty) return null;
    return InfographicBlock.fact(
      title: title,
      detail: detail,
      icon: c.icon,
      level: c.level,
      illustrationPrompt: c.prompt,
      illustrationRef: c.reference,
    );
  }

  static InfographicBlock? _titled(
    Map<String, Object?> j,
    _Common c,
    InfographicBlockKind kind,
  ) {
    var title = _text(j['title'] ?? j['label'], InfographicLimits.label);
    var detail = _text(j['detail'], InfographicLimits.detail);
    if (title.isEmpty) {
      title = _clamp(detail, InfographicLimits.label);
      detail = '';
    }
    if (title.isEmpty) return null;
    return kind == InfographicBlockKind.step
        ? InfographicBlock.step(
            title: title,
            detail: detail,
            icon: c.icon,
            level: c.level,
            illustrationPrompt: c.prompt,
            illustrationRef: c.reference,
          )
        : InfographicBlock.concept(
            title: title,
            detail: detail,
            icon: c.icon,
            level: c.level,
            illustrationPrompt: c.prompt,
            illustrationRef: c.reference,
          );
  }

  static InfographicBlock? _event(Map<String, Object?> j, _Common c) {
    final date = _text(j['date'], InfographicLimits.label);
    final title = _text(j['title'] ?? j['label'], InfographicLimits.label);
    if (date.isEmpty && title.isEmpty) return null;
    return InfographicBlock.event(
      date: date,
      title: title.isEmpty ? date : title,
      detail: _text(j['detail'], InfographicLimits.detail),
      icon: c.icon,
      level: c.level,
      illustrationPrompt: c.prompt,
      illustrationRef: c.reference,
    );
  }

  static InfographicBlock? _comparison(Map<String, Object?> j, _Common c) {
    final left = _side(j['left']);
    final right = _side(j['right']);
    if (left == null || right == null) return null;
    return InfographicBlock.comparison(
      title: _text(j['title'], InfographicLimits.label),
      left: left,
      right: right,
      conclusion: _text(j['conclusion'], InfographicLimits.detail),
      level: c.level,
      illustrationPrompt: c.prompt,
      illustrationRef: c.reference,
    );
  }

  static InfographicBlock? _quote(Map<String, Object?> j, _Common c) {
    final quote = _text(j['quote'] ?? j['detail'], InfographicLimits.quote);
    if (quote.isEmpty) return null;
    return InfographicBlock.quote(
      quote: _unquote(quote),
      author: _text(j['author'], InfographicLimits.attribution),
      source: _text(j['source'], InfographicLimits.attribution),
      level: c.level,
      illustrationPrompt: c.prompt,
      illustrationRef: c.reference,
    );
  }

  static InfographicBlock? _chart(Map<String, Object?> j, _Common c) {
    final data = _data(j['data'], j['labels'], j['values']);
    if (data.isEmpty) return null;
    final total = InfographicNumbers.parse(j['total']);
    return InfographicBlock.chart(
      title: _text(j['title'], InfographicLimits.label),
      chartKind: _chartKind(j['chart']),
      data: data,
      unit: _text(j['unit'], InfographicLimits.unit),
      total: total != null && total > 0 ? total : null,
      detail: _text(j['detail'], InfographicLimits.detail),
      level: c.level,
      illustrationPrompt: c.prompt,
      illustrationRef: c.reference,
    );
  }

  // ---------------------------------------------------------------------
  // Las piezas.

  /// Los bloques sueltos, o los de cada sección uno detrás de otro.
  static List<Object?> _rawBlocks(Map<String, Object?> sheet) {
    final blocks = _list(sheet['blocks']);
    if (blocks.isNotEmpty) return blocks;
    final out = <Object?>[];
    for (final section in _list(sheet['sections'])) {
      if (section is! Map) continue;
      final inner = _list(_normalizeKeys(section)['blocks']);
      out.addAll(inner.isEmpty ? [section] : inner);
    }
    return out;
  }

  static bool _hasLevels(List<Object?> raw) => raw.any(
    (b) => b is Map && _Common.levelOf(_normalizeKeys(b)['level']) != null,
  );

  /// Sin niveles escritos, se reparten por orden: la primera mitad es lo
  /// esencial; el siguiente cuarto, lo de apoyo; el resto, lo de más. La IA
  /// pone primero lo más importante.
  static List<InfographicBlock> _withLevels(
    List<InfographicBlock> blocks,
    bool explicit,
  ) {
    if (explicit) return blocks;
    final n = blocks.length;
    final essential = (n * 0.5).ceil();
    final supporting = (n * 0.75).ceil();
    return [
      for (var i = 0; i < n; i++)
        _relevel(
          blocks[i],
          i < essential
              ? InfographicLevel.essential
              : i < supporting
              ? InfographicLevel.supporting
              : InfographicLevel.extra,
        ),
    ];
  }

  static InfographicBlock _relevel(InfographicBlock b, InfographicLevel l) =>
      switch (b) {
        final StatBlock s => s.copyWith(level: l),
        final FactBlock s => s.copyWith(level: l),
        final StepBlock s => s.copyWith(level: l),
        final ComparisonBlock s => s.copyWith(level: l),
        final EventBlock s => s.copyWith(level: l),
        final ConceptBlock s => s.copyWith(level: l),
        final QuoteBlock s => s.copyWith(level: l),
        final ChartBlock s => s.copyWith(level: l),
      };

  /// Lo que no es JSON limpio: se busca el primer `{` o `[` y el último que
  /// lo cierra, para saltear el ```json y lo que la IA diga alrededor.
  static Object? _parseText(String text) {
    final trimmed = text.trim();
    try {
      return jsonDecode(trimmed);
    } on FormatException {
      // Sigue abajo.
    }
    final open = trimmed.indexOf(RegExp(r'[\{\[]'));
    if (open < 0) return null;
    final closer = trimmed[open] == '{' ? '}' : ']';
    final close = trimmed.lastIndexOf(closer);
    if (close <= open) return null;
    try {
      return jsonDecode(trimmed.substring(open, close + 1));
    } on FormatException {
      return null;
    }
  }

  /// Las claves llevadas a su nombre canónico: sin mayúsculas, guiones ni
  /// tildes, y los sinónimos en castellano o inglés que usa una IA.
  static Map<String, Object?> _normalizeKeys(Map<Object?, Object?> raw) {
    final out = <String, Object?>{};
    for (final entry in raw.entries) {
      final folded = _fold(entry.key.toString());
      final key = _keyAliases[folded] ?? folded;
      out.putIfAbsent(key, () => entry.value);
    }
    return out;
  }

  static String _fold(String key) => key
      .toLowerCase()
      .replaceAll(RegExp('[áà]'), 'a')
      .replaceAll(RegExp('[éè]'), 'e')
      .replaceAll(RegExp('[íì]'), 'i')
      .replaceAll(RegExp('[óò]'), 'o')
      .replaceAll(RegExp('[úùü]'), 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp('[^a-z0-9]'), '');

  static const Map<String, String> _keyAliases = {
    'titulo': 'title',
    'headline': 'title',
    'name': 'title',
    'nombre': 'title',
    'subtitulo': 'subtitle',
    'bajada': 'subtitle',
    'antetitulo': 'kicker',
    'eyebrow': 'kicker',
    'bloques': 'blocks',
    'items': 'blocks',
    'elementos': 'blocks',
    'secciones': 'sections',
    'kind': 'type',
    'tipo': 'type',
    'blocktype': 'type',
    'valor': 'value',
    'cifra': 'value',
    'number': 'value',
    'numero': 'value',
    'figure': 'value',
    'etiqueta': 'label',
    'rotulo': 'label',
    'detalle': 'detail',
    'description': 'detail',
    'descripcion': 'detail',
    'text': 'detail',
    'texto': 'detail',
    'body': 'detail',
    'icono': 'icon',
    'nivel': 'level',
    'priority': 'level',
    'prioridad': 'level',
    'importance': 'level',
    'importancia': 'level',
    'izquierda': 'left',
    'derecha': 'right',
    'heading': 'title',
    'encabezado': 'title',
    'puntos': 'points',
    'bullets': 'points',
    'vinetas': 'points',
    'conclusion': 'conclusion',
    'fecha': 'date',
    'year': 'date',
    'ano': 'date',
    'cita': 'quote',
    'autor': 'author',
    'fuente': 'source',
    'sources': 'source',
    'fuentes': 'source',
    'datos': 'data',
    'series': 'data',
    'etiquetas': 'labels',
    'valores': 'values',
    'unidad': 'unit',
    'charttype': 'chart',
    'grafico': 'chart',
    'tipodegrafico': 'chart',
    'max': 'total',
    'maximo': 'total',
    'of': 'total',
    'de': 'total',
    'idea': 'takeaway',
    'ideaclave': 'takeaway',
    'conclusiongeneral': 'takeaway',
    'parallevar': 'takeaway',
    'stylehint': 'style',
    'estilo': 'style',
    'compositionhint': 'composition',
    'composicion': 'composition',
    'layout': 'composition',
    'illustrationprompt': 'prompt',
    'imageprompt': 'prompt',
    'promptimagen': 'prompt',
    'ilustracion': 'prompt',
    'illustrationref': 'reference',
    'illustration': 'reference',
  };

  static InfographicBlockKind? _kind(Object? raw) {
    if (raw is! String) return null;
    final folded = _fold(raw);
    for (final kind in InfographicBlockKind.values) {
      if (_fold(kind.jsonName) == folded) return kind;
    }
    return _kindAliases[folded];
  }

  static const Map<String, InfographicBlockKind> _kindAliases = {
    'cifra': InfographicBlockKind.stat,
    'estadistica': InfographicBlockKind.stat,
    'statistic': InfographicBlockKind.stat,
    'number': InfographicBlockKind.stat,
    'numero': InfographicBlockKind.stat,
    'figure': InfographicBlockKind.stat,
    'bignumber': InfographicBlockKind.stat,
    'hecho': InfographicBlockKind.fact,
    'dato': InfographicBlockKind.fact,
    'idea': InfographicBlockKind.fact,
    'point': InfographicBlockKind.fact,
    'punto': InfographicBlockKind.fact,
    'paso': InfographicBlockKind.step,
    'etapa': InfographicBlockKind.step,
    'fase': InfographicBlockKind.step,
    'comparacion': InfographicBlockKind.comparison,
    'versus': InfographicBlockKind.comparison,
    'vs': InfographicBlockKind.comparison,
    'evento': InfographicBlockKind.event,
    'hito': InfographicBlockKind.event,
    'milestone': InfographicBlockKind.event,
    'timeline': InfographicBlockKind.event,
    'concepto': InfographicBlockKind.concept,
    'term': InfographicBlockKind.concept,
    'termino': InfographicBlockKind.concept,
    'cita': InfographicBlockKind.quote,
    'grafico': InfographicBlockKind.chart,
    'graph': InfographicBlockKind.chart,
    'barras': InfographicBlockKind.chart,
    'bars': InfographicBlockKind.chart,
  };

  /// El tipo que dicen los campos, si no vino escrito.
  static InfographicBlockKind _guessKind(Map<String, Object?> json) {
    if (json['data'] != null || json['values'] != null) {
      return InfographicBlockKind.chart;
    }
    if (json['left'] != null && json['right'] != null) {
      return InfographicBlockKind.comparison;
    }
    if (json['quote'] != null) return InfographicBlockKind.quote;
    if (json['date'] != null) return InfographicBlockKind.event;
    if (json['value'] != null) return InfographicBlockKind.stat;
    return InfographicBlockKind.fact;
  }

  static InfographicChartKind? _chartKind(Object? raw) {
    if (raw is! String) return null;
    final folded = _fold(raw);
    for (final kind in InfographicChartKind.values) {
      if (_fold(kind.jsonName) == folded) return kind;
    }
    return switch (folded) {
      'bar' || 'barras' || 'columns' || 'columnas' => InfographicChartKind.bars,
      'donut' ||
      'doughnut' ||
      'anillo' ||
      'pie' ||
      'torta' ||
      'dona' => InfographicChartKind.ring,
      'avance' ||
      'progreso' ||
      'meter' ||
      'gauge' => InfographicChartKind.progress,
      'pictograma' ||
      'icons' ||
      'iconos' ||
      'isotype' => InfographicChartKind.pictogram,
      _ => null,
    };
  }

  /// Los datos de un gráfico: una lista de objetos ({label, value}), de
  /// pares ([rótulo, valor]), un objeto {rótulo: valor}, o dos listas
  /// paralelas de rótulos y valores. Los que no traen un número se dejan.
  static List<InfographicDatum> _data(
    Object? raw,
    Object? labels,
    Object? values,
  ) {
    final out = <InfographicDatum>[];
    void add(Object? label, Object? value, [Object? display]) {
      if (out.length == InfographicLimits.data) return;
      final number = InfographicNumbers.parse(value);
      if (number == null) return;
      var shown = _text(display, InfographicLimits.value);
      if (shown.isEmpty && value is String) {
        shown = _text(value, InfographicLimits.value);
      }
      out.add(
        InfographicDatum(
          label: _text(label, InfographicLimits.label),
          value: number,
          display: shown,
        ),
      );
    }

    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          final d = _normalizeKeys(item);
          add(d['label'] ?? d['title'], d['value'], d['display']);
        } else if (item is List && item.length >= 2) {
          add(item[0], item[1]);
        } else if (item is num || item is String) {
          add('', item);
        }
      }
    } else if (raw is Map) {
      for (final entry in raw.entries) {
        add(entry.key.toString(), entry.value);
      }
    }
    if (out.isEmpty && values is List) {
      final names = labels is List ? labels : const <Object?>[];
      for (var i = 0; i < values.length; i++) {
        add(i < names.length ? names[i] : '', values[i]);
      }
    }
    return out;
  }

  /// Un nombre de estilo o de composición tal como se guarda (sin tildes ni
  /// mayúsculas, con guion bajo); null si no hay.
  static String? _hint(Object? raw) {
    if (raw is! String) return null;
    final hint = raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp('[áà]'), 'a')
        .replaceAll(RegExp('[éè]'), 'e')
        .replaceAll(RegExp('[íì]'), 'i')
        .replaceAll(RegExp('[óò]'), 'o')
        .replaceAll(RegExp('[úùü]'), 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[\s\-]+'), '_')
        .replaceAll(RegExp('[^a-z0-9_]'), '');
    return hint.isEmpty || hint.length > 40 ? null : hint;
  }

  static List<Object?> _list(Object? raw) => switch (raw) {
    final List<Object?> list => list,
    _ => const [],
  };

  /// Un texto limpio: los espacios repetidos en uno, sin bordes, cortado en
  /// [limit]. Un número se lee como su texto; lo demás, vacío.
  static String _text(Object? raw, int limit) {
    final String text;
    if (raw is String) {
      text = raw;
    } else if (raw is num) {
      text = raw is int || raw == raw.roundToDouble()
          ? raw.toInt().toString()
          : raw.toString();
    } else {
      return '';
    }
    return _clamp(text.replaceAll(RegExp(r'\s+'), ' ').trim(), limit);
  }

  /// Una lista de textos: una lista de verdad, o un texto con un punto por
  /// renglón (sin sus marcas «-», «•», «1.»).
  static List<String> _strings(Object? raw, int limit) {
    final items = <Object?>[
      if (raw is List) ...raw,
      if (raw is String) ...raw.split(RegExp(r'\n+')),
    ];
    final out = <String>[];
    for (final item in items) {
      final text = item is Map
          ? [
              for (final key in ['title', 'detail'])
                _text(_normalizeKeys(item)[key], limit),
            ].where((t) => t.isNotEmpty).join(': ')
          : _text(
              item is String
                  ? item.replaceFirst(RegExp(r'^\s*([-•*·▪●◦]|\d+[.)])\s*'), '')
                  : item,
              limit,
            );
      if (text.isNotEmpty) out.add(_clamp(text, limit));
    }
    return out;
  }

  static InfographicSide? _side(Object? raw) {
    if (raw is String || raw is List) {
      final points = _strings(raw, InfographicLimits.point);
      return points.isEmpty
          ? null
          : InfographicSide(
              points: points.take(InfographicLimits.points).toList(),
            );
    }
    if (raw is! Map) return null;
    final json = _normalizeKeys(raw);
    final heading = _text(json['title'], InfographicLimits.label);
    final points = _strings(
      json['points'] ?? json['detail'],
      InfographicLimits.point,
    ).take(InfographicLimits.points).toList();
    if (heading.isEmpty && points.isEmpty) return null;
    final icon = _text(json['icon'], InfographicLimits.icon);
    return InfographicSide(
      heading: heading,
      points: points,
      icon: icon.isEmpty ? null : icon,
    );
  }

  /// Sin las comillas con que la IA a veces envuelve una cita: el diseño
  /// dibuja las suyas.
  static String _unquote(String text) {
    final match = RegExp(r'^["“«‘\x27]+(.*?)["”»’\x27]+$').firstMatch(text);
    return match == null ? text : match.group(1)!.trim();
  }

  /// [text] cortado en [limit] caracteres, en la última palabra entera, con
  /// «…».
  static String _clamp(String text, int limit) {
    if (text.length <= limit) return text;
    final cut = text.substring(0, limit - 1);
    final space = cut.lastIndexOf(' ');
    final head = space > limit * 0.6 ? cut.substring(0, space) : cut;
    return '${head.replaceFirst(RegExp(r'[\s,;:.—-]+$'), '')}…';
  }
}

/// Lo que comparten todos los bloques (y la cabecera).
class _Common {
  const _Common(this.prompt, this.reference, this.icon, this.level);

  factory _Common.of(Map<String, Object?> json) {
    final prompt = InfographicJson._text(
      json['prompt'],
      InfographicLimits.prompt,
    );
    final reference = json['reference'] is String
        ? (json['reference']! as String).trim()
        : '';
    final icon = InfographicJson._text(json['icon'], InfographicLimits.icon);
    return _Common(
      prompt.isEmpty ? null : prompt,
      reference.isEmpty || reference.length > InfographicLimits.reference
          ? null
          : reference,
      icon.isEmpty ? null : icon,
      levelOf(json['level']) ?? InfographicLevel.essential,
    );
  }

  /// El nivel escrito como número (1 a 3) o como palabra.
  static InfographicLevel? levelOf(Object? raw) {
    if (raw is num) {
      return InfographicLevel.fromValue(raw.round().clamp(1, 3));
    }
    if (raw is! String) return null;
    final folded = InfographicJson._fold(raw);
    final number = int.tryParse(folded);
    if (number != null) return InfographicLevel.fromValue(number.clamp(1, 3));
    return switch (folded) {
      'essential' ||
      'esencial' ||
      'high' ||
      'alta' ||
      'alto' ||
      'core' ||
      'key' ||
      'clave' ||
      'principal' => InfographicLevel.essential,
      'supporting' ||
      'apoyo' ||
      'medium' ||
      'media' ||
      'medio' ||
      'standard' ||
      'estandar' => InfographicLevel.supporting,
      'extra' ||
      'low' ||
      'baja' ||
      'bajo' ||
      'detail' ||
      'detalle' ||
      'detailed' ||
      'detallado' => InfographicLevel.extra,
      _ => null,
    };
  }

  final String? prompt;
  final String? reference;
  final String? icon;
  final InfographicLevel level;
}
