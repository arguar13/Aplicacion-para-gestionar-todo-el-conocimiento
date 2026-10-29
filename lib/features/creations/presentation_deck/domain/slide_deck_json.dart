import 'dart:convert';

import 'package:sinapsis/features/creations/presentation_deck/domain/slide.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck.dart';

/// Los topes de cada campo: lo que no entra se corta en la última palabra
/// entera, con «…». Son generosos —el dibujo además achica la letra para
/// que entre—, pero ponen un límite a lo que una IA desbocada puede
/// devolver.
abstract final class SlideLimits {
  static const int slides = 40;
  static const int title = 120;
  static const int subtitle = 220;
  static const int kicker = 60;
  static const int bullet = 240;
  static const int body = 700;
  static const int quote = 420;
  static const int attribution = 120;
  static const int value = 18;
  static const int label = 140;
  static const int detail = 260;
  static const int notes = 4000;
  static const int prompt = 500;
  static const int reference = 1024;
  static const int icon = 40;

  static const int bullets = 7;
  static const int columnPoints = 6;
  static const int steps = 6;
  static const int events = 6;
  static const int concepts = 6;
  static const int takeaways = 4;
}

/// El JSON de un mazo, en los dos sentidos (F43, decisión G).
///
/// [decode] lee con tolerancia lo que devuelve la IA —y lo guardado—: acepta
/// el JSON envuelto en ```json o con texto alrededor, las claves en
/// camelCase, snake_case o castellano, listas escritas como un texto con
/// renglones, y números donde iba un texto. Un diseño desconocido se lee
/// como viñetas con todo el texto que traiga; uno al que le falta lo suyo
/// (una cronología sin hitos) también; una diapositiva sin nada de texto se
/// descarta. Nunca falla por un campo: falla solo si no hay ningún mazo que
/// leer (ver [tryDecode]).
///
/// [encode] escribe la forma canónica, la que se guarda en «Lo creado» y la
/// que describe `slideDeckJsonSchemaPrompt`.
abstract final class SlideDeckJson {
  /// El mazo de [source] —un `Map`, una lista de diapositivas o el texto que
  /// devolvió la IA—, o null si ahí no hay ninguna diapositiva legible (es
  /// lo que hace que se le pida a la IA que lo corrija).
  static SlideDeck? tryDecode(Object? source) {
    final json = source is String ? _parseText(source) : source;
    final Map<String, Object?> deck;
    if (json is List) {
      deck = {'slides': json};
    } else if (json is Map) {
      deck = _normalizeKeys(json);
    } else {
      return null;
    }
    final slides = <Slide>[];
    for (final raw in _list(deck['slides'])) {
      final slide = decodeSlide(raw);
      if (slide != null) slides.add(slide);
      if (slides.length == SlideLimits.slides) break;
    }
    if (slides.isEmpty) return null;
    final title = _text(deck['title'], SlideLimits.title);
    return SlideDeck(
      title: title.isNotEmpty ? title : slides.first.headline,
      subtitle: _text(deck['subtitle'], SlideLimits.subtitle),
      format: _format(deck['format']),
      slides: slides,
    );
  }

  /// Como [tryDecode], pero sin ninguna diapositiva devuelve un mazo vacío
  /// en vez de null: para leer lo guardado, que ya pasó por acá una vez.
  static SlideDeck decode(Object? source) =>
      tryDecode(source) ?? const SlideDeck(title: '');

  static Map<String, Object?> encode(SlideDeck deck) => {
    'title': deck.title,
    if (deck.subtitle.isNotEmpty) 'subtitle': deck.subtitle,
    'format': deck.format.jsonName,
    'slides': [for (final slide in deck.slides) encodeSlide(slide)],
  };

  static String encodeString(SlideDeck deck) => jsonEncode(encode(deck));

  /// Una diapositiva, o null si no trae nada de texto.
  static Slide? decodeSlide(Object? raw) {
    if (raw is! Map) return null;
    final json = _normalizeKeys(raw);
    final layout = _layout(json['layout']);
    final common = _Common.of(json);
    final slide = switch (layout) {
      SlideLayout.cover => _cover(json, common),
      SlideLayout.section => _section(json, common),
      SlideLayout.bullets => null,
      SlideLayout.twoColumns => _twoColumns(json, common),
      SlideLayout.quote => _quote(json, common),
      SlideLayout.bigNumber => _bigNumber(json, common),
      SlideLayout.steps => _steps(json, common),
      SlideLayout.comparison => _comparison(json, common),
      SlideLayout.timeline => _timeline(json, common),
      SlideLayout.imageText => _imageText(json, common),
      SlideLayout.conceptGrid => _conceptGrid(json, common),
      SlideLayout.closing => _closing(json, common),
      null => null,
    };
    // Las viñetas son también la red de un diseño desconocido o al que le
    // falta lo suyo: se juntan todos los textos que haya.
    return slide ?? _bullets(json, common);
  }

  static Map<String, Object?> encodeSlide(Slide slide) {
    final json = <String, Object?>{'layout': slide.layout.jsonName};
    void put(String key, String value) {
      if (value.isNotEmpty) json[key] = value;
    }

    void putList(String key, List<Object?> values) {
      if (values.isNotEmpty) json[key] = values;
    }

    Map<String, Object?> column(SlideColumn c) => {
      if (c.heading.isNotEmpty) 'heading': c.heading,
      'points': c.points,
    };

    switch (slide) {
      case CoverSlide(:final title, :final subtitle, :final kicker):
        put('title', title);
        put('subtitle', subtitle);
        put('kicker', kicker);
      case SectionSlide(:final title, :final subtitle):
        put('title', title);
        put('subtitle', subtitle);
      case BulletsSlide(:final title, :final bullets):
        put('title', title);
        putList('bullets', bullets);
      case TwoColumnsSlide(:final title, :final left, :final right):
        put('title', title);
        json['left'] = column(left);
        json['right'] = column(right);
      case QuoteSlide(:final quote, :final author, :final source):
        put('quote', quote);
        put('author', author);
        put('source', source);
      case BigNumberSlide(
        :final title,
        :final value,
        :final label,
        :final detail,
      ):
        put('title', title);
        put('value', value);
        put('label', label);
        put('detail', detail);
      case StepsSlide(:final title, :final steps):
        put('title', title);
        putList('steps', [
          for (final s in steps)
            {'title': s.title, if (s.detail.isNotEmpty) 'detail': s.detail},
        ]);
      case ComparisonSlide(
        :final title,
        :final left,
        :final right,
        :final conclusion,
      ):
        put('title', title);
        json['left'] = column(left);
        json['right'] = column(right);
        put('conclusion', conclusion);
      case TimelineSlide(:final title, :final events):
        put('title', title);
        putList('events', [
          for (final e in events)
            {
              'date': e.date,
              'title': e.title,
              if (e.detail.isNotEmpty) 'detail': e.detail,
            },
        ]);
      case ImageTextSlide(:final title, :final body, :final bullets):
        put('title', title);
        put('body', body);
        putList('bullets', bullets);
      case ConceptGridSlide(:final title, :final concepts):
        put('title', title);
        putList('concepts', [
          for (final c in concepts)
            {
              'title': c.title,
              if (c.detail.isNotEmpty) 'detail': c.detail,
              if (c.icon != null) 'icon': c.icon,
            },
        ]);
      case ClosingSlide(:final title, :final subtitle, :final takeaways):
        put('title', title);
        put('subtitle', subtitle);
        putList('takeaways', takeaways);
    }
    put('illustration_prompt', slide.illustrationPrompt ?? '');
    put('illustration_ref', slide.illustrationRef ?? '');
    put('speaker_notes', slide.speakerNotes);
    return json;
  }

  // ---------------------------------------------------------------------
  // Cada diseño. Devuelven null si les falta lo que los define, y entonces
  // la diapositiva se lee como viñetas.

  static Slide? _cover(Map<String, Object?> j, _Common c) {
    final title = _text(j['title'], SlideLimits.title);
    if (title.isEmpty) return null;
    return Slide.cover(
      title: title,
      subtitle: _text(j['subtitle'], SlideLimits.subtitle),
      kicker: _text(j['kicker'], SlideLimits.kicker),
      illustrationPrompt: c.prompt,
      illustrationRef: c.reference,
      speakerNotes: c.notes,
    );
  }

  static Slide? _section(Map<String, Object?> j, _Common c) {
    final title = _text(j['title'], SlideLimits.title);
    if (title.isEmpty) return null;
    return Slide.section(
      title: title,
      subtitle: _text(j['subtitle'], SlideLimits.subtitle),
      illustrationPrompt: c.prompt,
      illustrationRef: c.reference,
      speakerNotes: c.notes,
    );
  }

  static Slide? _bullets(Map<String, Object?> j, _Common c) {
    final title = _text(j['title'], SlideLimits.title);
    final bullets = _strings(j['bullets'], SlideLimits.bullet);
    // Lo que traiga otro diseño, para no perderlo.
    if (bullets.isEmpty) {
      bullets
        ..addAll(_strings(j['points'], SlideLimits.bullet))
        ..addAll([
          for (final s in _list(j['steps'])) ..._joinedTexts(s),
          for (final e in _list(j['events'])) ..._joinedTexts(e),
          for (final k in _list(j['concepts'])) ..._joinedTexts(k),
        ]);
      for (final side in [j['left'], j['right']]) {
        if (side is Map) {
          final column = _normalizeKeys(side);
          bullets.addAll(_strings(column['points'], SlideLimits.bullet));
        }
      }
      bullets.addAll(_strings(j['takeaways'], SlideLimits.bullet));
      final loose = [
        _text(j['quote'], SlideLimits.bullet),
        _text(j['body'], SlideLimits.bullet),
        _text(j['value'], SlideLimits.bullet),
        _text(j['label'], SlideLimits.bullet),
        _text(j['detail'], SlideLimits.bullet),
        _text(j['subtitle'], SlideLimits.bullet),
        _text(j['conclusion'], SlideLimits.bullet),
      ].where((t) => t.isNotEmpty);
      bullets.addAll(loose);
    }
    final kept = bullets.take(SlideLimits.bullets).toList();
    if (title.isEmpty && kept.isEmpty) return null;
    return Slide.bullets(
      title: title,
      bullets: kept,
      illustrationPrompt: c.prompt,
      illustrationRef: c.reference,
      speakerNotes: c.notes,
    );
  }

  static Slide? _twoColumns(Map<String, Object?> j, _Common c) {
    final left = _column(j['left']);
    final right = _column(j['right']);
    if (left == null || right == null) return null;
    return Slide.twoColumns(
      title: _text(j['title'], SlideLimits.title),
      left: left,
      right: right,
      illustrationPrompt: c.prompt,
      illustrationRef: c.reference,
      speakerNotes: c.notes,
    );
  }

  static Slide? _quote(Map<String, Object?> j, _Common c) {
    final quote = _text(j['quote'] ?? j['body'], SlideLimits.quote);
    if (quote.isEmpty) return null;
    return Slide.quote(
      quote: _unquote(quote),
      author: _text(j['author'], SlideLimits.attribution),
      source: _text(j['source'], SlideLimits.attribution),
      illustrationPrompt: c.prompt,
      illustrationRef: c.reference,
      speakerNotes: c.notes,
    );
  }

  static Slide? _bigNumber(Map<String, Object?> j, _Common c) {
    final value = _text(j['value'], SlideLimits.value);
    if (value.isEmpty) return null;
    return Slide.bigNumber(
      value: value,
      title: _text(j['title'], SlideLimits.title),
      label: _text(j['label'], SlideLimits.label),
      detail: _text(j['detail'], SlideLimits.detail),
      illustrationPrompt: c.prompt,
      illustrationRef: c.reference,
      speakerNotes: c.notes,
    );
  }

  static Slide? _steps(Map<String, Object?> j, _Common c) {
    final steps = <SlideStep>[];
    for (final raw in _list(j['steps'])) {
      final pair = _titleDetail(raw);
      if (pair != null) steps.add(SlideStep(title: pair.$1, detail: pair.$2));
      if (steps.length == SlideLimits.steps) break;
    }
    if (steps.length < 2) return null;
    return Slide.steps(
      title: _text(j['title'], SlideLimits.title),
      steps: steps,
      illustrationPrompt: c.prompt,
      illustrationRef: c.reference,
      speakerNotes: c.notes,
    );
  }

  static Slide? _comparison(Map<String, Object?> j, _Common c) {
    final left = _column(j['left']);
    final right = _column(j['right']);
    if (left == null || right == null) return null;
    return Slide.comparison(
      title: _text(j['title'], SlideLimits.title),
      left: left,
      right: right,
      conclusion: _text(j['conclusion'], SlideLimits.detail),
      illustrationPrompt: c.prompt,
      illustrationRef: c.reference,
      speakerNotes: c.notes,
    );
  }

  static Slide? _timeline(Map<String, Object?> j, _Common c) {
    final events = <TimelineEvent>[];
    for (final raw in _list(j['events'])) {
      if (raw is! Map) continue;
      final e = _normalizeKeys(raw);
      final date = _text(e['date'], SlideLimits.label);
      final title = _text(e['title'], SlideLimits.label);
      if (date.isEmpty && title.isEmpty) continue;
      events.add(
        TimelineEvent(
          date: date,
          title: title,
          detail: _text(e['detail'], SlideLimits.detail),
        ),
      );
      if (events.length == SlideLimits.events) break;
    }
    if (events.length < 2) return null;
    return Slide.timeline(
      title: _text(j['title'], SlideLimits.title),
      events: events,
      illustrationPrompt: c.prompt,
      illustrationRef: c.reference,
      speakerNotes: c.notes,
    );
  }

  static Slide? _imageText(Map<String, Object?> j, _Common c) {
    final title = _text(j['title'], SlideLimits.title);
    final body = _text(j['body'], SlideLimits.body);
    final bullets = _strings(j['bullets'], SlideLimits.bullet).take(4).toList();
    if (title.isEmpty && body.isEmpty && bullets.isEmpty) return null;
    return Slide.imageText(
      title: title,
      body: body,
      bullets: bullets,
      illustrationPrompt: c.prompt,
      illustrationRef: c.reference,
      speakerNotes: c.notes,
    );
  }

  static Slide? _conceptGrid(Map<String, Object?> j, _Common c) {
    final concepts = <SlideConcept>[];
    for (final raw in _list(j['concepts'])) {
      final pair = _titleDetail(raw);
      if (pair == null) continue;
      final icon = raw is Map
          ? _text(_normalizeKeys(raw)['icon'], SlideLimits.icon)
          : '';
      concepts.add(
        SlideConcept(
          title: pair.$1,
          detail: pair.$2,
          icon: icon.isEmpty ? null : icon,
        ),
      );
      if (concepts.length == SlideLimits.concepts) break;
    }
    if (concepts.length < 2) return null;
    return Slide.conceptGrid(
      title: _text(j['title'], SlideLimits.title),
      concepts: concepts,
      illustrationPrompt: c.prompt,
      illustrationRef: c.reference,
      speakerNotes: c.notes,
    );
  }

  static Slide? _closing(Map<String, Object?> j, _Common c) {
    final title = _text(j['title'], SlideLimits.title);
    if (title.isEmpty) return null;
    return Slide.closing(
      title: title,
      subtitle: _text(j['subtitle'], SlideLimits.subtitle),
      takeaways: _strings(
        j['takeaways'] ?? j['bullets'],
        SlideLimits.bullet,
      ).take(SlideLimits.takeaways).toList(),
      illustrationPrompt: c.prompt,
      illustrationRef: c.reference,
      speakerNotes: c.notes,
    );
  }

  // ---------------------------------------------------------------------
  // Las piezas.

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
    'heading': 'title',
    'headline': 'title',
    'subtitulo': 'subtitle',
    'bajada': 'subtitle',
    'antetitulo': 'kicker',
    'eyebrow': 'kicker',
    'diapositivas': 'slides',
    'formato': 'format',
    'type': 'layout',
    'tipo': 'layout',
    'diseno': 'layout',
    'kind': 'layout',
    'vinetas': 'bullets',
    'items': 'bullets',
    'puntos': 'points',
    'izquierda': 'left',
    'derecha': 'right',
    'cita': 'quote',
    'autor': 'author',
    'fuente': 'source',
    'valor': 'value',
    'cifra': 'value',
    'number': 'value',
    'numero': 'value',
    'etiqueta': 'label',
    'detalle': 'detail',
    'description': 'detail',
    'descripcion': 'detail',
    'pasos': 'steps',
    'conclusion': 'conclusion',
    'hitos': 'events',
    'eventos': 'events',
    'fecha': 'date',
    'year': 'date',
    'ano': 'date',
    'cuerpo': 'body',
    'texto': 'body',
    'text': 'body',
    'paragraph': 'body',
    'conceptos': 'concepts',
    'icono': 'icon',
    'ideasclave': 'takeaways',
    'conclusiones': 'takeaways',
    'speakernotes': 'notes',
    'notasdelpresentador': 'notes',
    'notas': 'notes',
    'illustrationprompt': 'prompt',
    'imageprompt': 'prompt',
    'promptimagen': 'prompt',
    'ilustracion': 'prompt',
    'illustrationref': 'reference',
    'illustration': 'reference',
  };

  static SlideLayout? _layout(Object? raw) {
    if (raw is! String) return null;
    final folded = _fold(raw);
    for (final layout in SlideLayout.values) {
      if (_fold(layout.jsonName) == folded || _fold(layout.name) == folded) {
        return layout;
      }
    }
    return _layoutAliases[folded];
  }

  static const Map<String, SlideLayout> _layoutAliases = {
    'portada': SlideLayout.cover,
    'title': SlideLayout.cover,
    'titulo': SlideLayout.cover,
    'seccion': SlideLayout.section,
    'separador': SlideLayout.section,
    'vinetas': SlideLayout.bullets,
    'lista': SlideLayout.bullets,
    'list': SlideLayout.bullets,
    'doscolumnas': SlideLayout.twoColumns,
    'columns': SlideLayout.twoColumns,
    'cita': SlideLayout.quote,
    'cifra': SlideLayout.bigNumber,
    'cifradestacada': SlideLayout.bigNumber,
    'stat': SlideLayout.bigNumber,
    'number': SlideLayout.bigNumber,
    'pasos': SlideLayout.steps,
    'lineadepasos': SlideLayout.steps,
    'process': SlideLayout.steps,
    'comparacion': SlideLayout.comparison,
    'versus': SlideLayout.comparison,
    'cronologia': SlideLayout.timeline,
    'lineadetiempo': SlideLayout.timeline,
    'imagencontexto': SlideLayout.imageText,
    'imagen': SlideLayout.imageText,
    'image': SlideLayout.imageText,
    'cuadriculadeconceptos': SlideLayout.conceptGrid,
    'conceptos': SlideLayout.conceptGrid,
    'grid': SlideLayout.conceptGrid,
    'cierre': SlideLayout.closing,
    'conclusion': SlideLayout.closing,
    'end': SlideLayout.closing,
  };

  static DeckFormat _format(Object? raw) {
    if (raw is! String) return DeckFormat.detailed;
    final folded = _fold(raw);
    return folded.contains('present')
        ? DeckFormat.presenter
        : DeckFormat.detailed;
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
    return clamp(text.replaceAll(RegExp(r'\s+'), ' ').trim(), limit);
  }

  /// Una lista de textos: una lista de verdad, un texto con un punto por
  /// renglón (sin sus marcas «-», «•», «1.»), o una lista de objetos con su
  /// texto adentro.
  static List<String> _strings(Object? raw, int limit) {
    final items = <Object?>[
      if (raw is List) ...raw,
      if (raw is String) ...raw.split(RegExp(r'\n+')),
    ];
    final out = <String>[];
    for (final item in items) {
      final text = item is Map
          ? _joinedTexts(item).join(': ')
          : _text(
              item is String
                  ? item.replaceFirst(RegExp(r'^\s*([-•*·▪●◦]|\d+[.)])\s*'), '')
                  : item,
              limit,
            );
      if (text.isNotEmpty) out.add(clamp(text, limit));
    }
    return out;
  }

  /// Los textos de un objeto, en un orden razonable: título, detalle y lo
  /// demás.
  static List<String> _joinedTexts(Object? raw) {
    if (raw is String) {
      final text = _text(raw, SlideLimits.bullet);
      return text.isEmpty ? const [] : [text];
    }
    if (raw is! Map) return const [];
    final json = _normalizeKeys(raw);
    final parts = [
      for (final key in ['date', 'title', 'body', 'detail'])
        _text(json[key], SlideLimits.bullet),
    ].where((t) => t.isNotEmpty).toList();
    return parts.isEmpty ? const [] : [parts.join(' — ')];
  }

  /// Un paso o un concepto: un objeto con título y detalle, o un texto solo.
  static (String, String)? _titleDetail(Object? raw) {
    if (raw is String) {
      final title = _text(raw, SlideLimits.label);
      return title.isEmpty ? null : (title, '');
    }
    if (raw is! Map) return null;
    final json = _normalizeKeys(raw);
    var title = _text(json['title'], SlideLimits.label);
    var detail = _text(json['detail'] ?? json['body'], SlideLimits.detail);
    if (title.isEmpty) {
      title = clamp(detail, SlideLimits.label);
      detail = '';
    }
    return title.isEmpty ? null : (title, detail);
  }

  static SlideColumn? _column(Object? raw) {
    if (raw is String || raw is List) {
      final points = _strings(raw, SlideLimits.bullet);
      return points.isEmpty
          ? null
          : SlideColumn(points: points.take(SlideLimits.columnPoints).toList());
    }
    if (raw is! Map) return null;
    final json = _normalizeKeys(raw);
    final heading = _text(json['title'], SlideLimits.label);
    final points = _strings(
      json['points'] ?? json['bullets'],
      SlideLimits.bullet,
    ).take(SlideLimits.columnPoints).toList();
    if (heading.isEmpty && points.isEmpty) return null;
    return SlideColumn(heading: heading, points: points);
  }

  /// Sin las comillas con que la IA a veces envuelve una cita: el diseño
  /// dibuja las suyas.
  static String _unquote(String text) {
    final match = RegExp(r'^["“«‘\x27]+(.*?)["”»’\x27]+$').firstMatch(text);
    return match == null ? text : match.group(1)!.trim();
  }

  /// [text] cortado en [limit] caracteres, en la última palabra entera, con
  /// «…».
  static String clamp(String text, int limit) {
    if (text.length <= limit) return text;
    final cut = text.substring(0, limit - 1);
    final space = cut.lastIndexOf(' ');
    final head = space > limit * 0.6 ? cut.substring(0, space) : cut;
    return '${head.replaceFirst(RegExp(r'[\s,;:.—-]+$'), '')}…';
  }
}

/// Lo que comparten todas las diapositivas.
class _Common {
  const _Common(this.prompt, this.reference, this.notes);

  factory _Common.of(Map<String, Object?> json) {
    final prompt = SlideDeckJson._text(json['prompt'], SlideLimits.prompt);
    final reference = json['reference'] is String
        ? (json['reference']! as String).trim()
        : '';
    final notes = json['notes'];
    return _Common(
      prompt.isEmpty ? null : prompt,
      reference.isEmpty || reference.length > SlideLimits.reference
          ? null
          : reference,
      notes is List
          ? SlideDeckJson.clamp(
              SlideDeckJson._strings(notes, SlideLimits.notes).join('\n'),
              SlideLimits.notes,
            )
          : _notes(notes),
    );
  }

  /// Las notas conservan sus renglones: se dicen en voz alta, y un párrafo
  /// por idea se lee mejor.
  static String _notes(Object? raw) {
    if (raw is! String) return '';
    final text = raw
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return SlideDeckJson.clamp(text, SlideLimits.notes);
  }

  final String? prompt;
  final String? reference;
  final String notes;
}
