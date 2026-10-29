import 'dart:convert';

import 'package:sinapsis/features/creations/domain/services/structured_json.dart';
import 'package:sinapsis/features/creations/report/domain/report.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';

/// Los topes de cada campo: lo que no entra se corta en la última palabra
/// entera, con «…». Son generosos, pero le ponen un límite a lo que una IA
/// desbocada puede devolver.
abstract final class ReportLimits {
  static const int title = 160;
  static const int subtitle = 320;
  static const int sections = 16;
  static const int sectionTitle = 140;
  static const int body = 8000;
  static const int entries = 80;
  static const int term = 120;
  static const int definition = 700;
  static const int questions = 3;
  static const int question = 400;
  static const int options = 5;
  static const int option = 260;
  static const int why = 400;
  static const int explanation = 700;
  static const int keywords = 40;
  static const int keyword = 60;
}

/// El JSON de un informe, en los dos sentidos (F43, decisión G).
///
/// [tryDecode] lee con tolerancia lo que devuelve la IA —y lo guardado—:
/// acepta las claves en camelCase, snake_case o castellano («secciones»,
/// «título», «preguntas»), el texto de una sección como un texto, como una
/// lista de párrafos o como viñetas sueltas, los términos del glosario como
/// lista o como un objeto `{término: definición}`, y la respuesta correcta
/// de una pregunta marcada en la opción («correct»: true), como número
/// —desde 0 o desde 1—, como letra («B») o como el texto de la opción. Una
/// pregunta que no se puede leer entera —sin dos opciones, sin cuál es la
/// correcta— se deja afuera; nunca hace fallar el informe. Falla solo si no
/// hay ninguna sección con algo para leer.
///
/// [encode] escribe la forma canónica, la que se guarda en «Lo creado» y la
/// que describe `reportJsonSchemaPrompt`.
abstract final class ReportJson {
  /// El informe de [source] —un `Map`, una lista de secciones o el texto que
  /// devolvió la IA—, o `null` si ahí no hay ninguna sección legible.
  static Report? tryDecode(Object? source) {
    var json = source;
    if (json is String) {
      try {
        json = extractJsonValue(json);
      } on FormatException {
        return null;
      }
    }
    final Map<String, Object?> root;
    if (json is List) {
      root = {'sections': json};
    } else if (json is Map) {
      root = _normalized(json);
      // Un informe envuelto: {"informe": {...}} o {"report": {...}}.
      final wrapped = _pick(root, _reportKeys);
      if (_pick(root, _sectionsKeys) == null && wrapped is Map) {
        return tryDecode(wrapped);
      }
    } else {
      return null;
    }

    final sections = <ReportSection>[];
    final raw = _pick(root, _sectionsKeys);
    for (final item in raw is List ? raw : const []) {
      final section = decodeSection(item);
      if (section != null) sections.add(section);
      if (sections.length == ReportLimits.sections) break;
    }
    if (!sections.any((s) => s.hasContent)) return null;

    final keywords = <String>[];
    final seen = <String>{};
    final rawKeywords = _pick(root, _keywordsKeys);
    for (final item in rawKeywords is List ? rawKeywords : const []) {
      final keyword = _text(item, ReportLimits.keyword);
      if (keyword.isEmpty || !seen.add(foldStudyWord(keyword))) continue;
      keywords.add(keyword);
      if (keywords.length == ReportLimits.keywords) break;
    }

    return Report(
      title: _text(_pick(root, _titleKeys), ReportLimits.title),
      subtitle: _text(_pick(root, _subtitleKeys), ReportLimits.subtitle),
      sections: sections,
      keywords: keywords,
    );
  }

  /// Como [tryDecode], pero sin ninguna sección devuelve un informe vacío
  /// en vez de `null`: para leer lo guardado, que ya pasó por acá una vez.
  static Report decode(Object? source) =>
      tryDecode(source) ?? const Report(title: '');

  /// Una sección, o `null` si no trae nada: ni texto, ni términos, ni
  /// preguntas.
  static ReportSection? decodeSection(Object? raw) {
    if (raw is String) {
      final body = _clamp(raw.trim(), ReportLimits.body);
      return body.isEmpty ? null : ReportSection(title: '', body: body);
    }
    if (raw is! Map) return null;
    final json = _normalized(raw);
    final title = _text(_pick(json, _titleKeys), ReportLimits.sectionTitle);
    final body = _body(json);
    final entries = _entries(_pick(json, _entriesKeys));
    final questions = <ReportQuestion>[];
    final rawQuestions = _pick(json, _questionsKeys);
    for (final item in rawQuestions is List ? rawQuestions : const []) {
      final question = decodeQuestion(item);
      if (question != null) questions.add(question);
      if (questions.length == ReportLimits.questions) break;
    }
    if (body.isEmpty && entries.isEmpty && questions.isEmpty) return null;
    return ReportSection(
      title: title,
      body: body,
      entries: entries,
      questions: questions,
    );
  }

  /// Una pregunta, o `null` si no se puede hacer: sin enunciado, sin dos
  /// opciones distintas o sin saber cuál es la correcta.
  static ReportQuestion? decodeQuestion(Object? raw) {
    if (raw is! Map) return null;
    final json = _normalized(raw);
    final text = _text(_pick(json, _questionTextKeys), ReportLimits.question);
    if (text.isEmpty) return null;
    final rawOptions = _pick(json, _optionsKeys);
    final options = <ReportOption>[];
    final seen = <String>{};
    int? markedCorrect;
    var sourceIndex = -1;
    // De qué lugar de la lista original vino cada opción leída: la respuesta
    // como número cuenta sobre la lista que escribió la IA.
    final fromIndex = <int, int>{};
    for (final item in rawOptions is List ? rawOptions : const []) {
      sourceIndex++;
      final String option;
      var why = '';
      var correct = false;
      if (item is Map) {
        final o = _normalized(item);
        option = _text(_pick(o, _optionTextKeys), ReportLimits.option);
        why = _text(_pick(o, _whyKeys), ReportLimits.why);
        correct = _truthy(_pick(o, _correctFlagKeys));
      } else {
        option = _text(item, ReportLimits.option);
      }
      if (option.isEmpty || !seen.add(foldStudyWord(option))) continue;
      if (options.length == ReportLimits.options) break;
      fromIndex[sourceIndex] = options.length;
      if (correct && markedCorrect == null) markedCorrect = options.length;
      options.add(ReportOption(text: option, why: why));
    }
    if (options.length < 2) return null;

    final answer =
        markedCorrect ??
        _answerIndex(
          _pick(json, _answerKeys),
          options,
          fromIndex,
          sourceIndex + 1,
        );
    if (answer == null) return null;

    // Los porqués también pueden venir aparte, en una lista paralela.
    final whys = _pick(json, _whyListKeys);
    if (whys is List) {
      for (final MapEntry(key: source, value: target) in fromIndex.entries) {
        if (source < whys.length && options[target].why.isEmpty) {
          options[target] = options[target].copyWith(
            why: _text(whys[source], ReportLimits.why),
          );
        }
      }
    }
    return ReportQuestion(
      question: text,
      options: options,
      answer: answer,
      explanation: _text(
        _pick(json, _explanationKeys),
        ReportLimits.explanation,
      ),
    );
  }

  /// Cuál es la correcta, dicha como número, letra o texto.
  static int? _answerIndex(
    Object? given,
    List<ReportOption> options,
    Map<int, int> fromIndex,
    int written,
  ) {
    var raw = given;
    if (raw is List && raw.isNotEmpty) raw = raw.first;
    if (raw is Map) {
      final o = _normalized(raw);
      raw = _pick(o, _optionTextKeys) ?? _pick(o, const ['index', 'indice']);
    }
    int? fromNumber(num value) {
      final n = value.toInt();
      if (n != value) return null;
      // Desde 0, lo que pide el esquema; un número igual a la cantidad de
      // opciones que escribió solo puede ser desde 1.
      final source = n == written ? n - 1 : n;
      return fromIndex[source];
    }

    if (raw is num) return fromNumber(raw);
    if (raw is! String) return null;
    final text = raw.trim();
    if (text.isEmpty) return null;
    final number = int.tryParse(text);
    if (number != null) return fromNumber(number);
    // «B», «b)», «Opción B».
    final letter = RegExp(
      r'^(?:opci[oó]n\s+|option\s+)?([a-e])[).:]?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (letter != null) {
      final source = letter.group(1)!.toLowerCase().codeUnitAt(0) - 0x61;
      return fromIndex[source];
    }
    final folded = foldStudyWord(text);
    for (final (i, option) in options.indexed) {
      if (foldStudyWord(option.text) == folded) return i;
    }
    return null;
  }

  static Map<String, Object?> encode(Report report) => {
    'title': report.title,
    if (report.subtitle.isNotEmpty) 'subtitle': report.subtitle,
    'sections': [for (final section in report.sections) encodeSection(section)],
    if (report.keywords.isNotEmpty) 'keywords': report.keywords,
  };

  static String encodeString(Report report) => jsonEncode(encode(report));

  static Map<String, Object?> encodeSection(ReportSection section) => {
    'title': section.title,
    if (section.body.isNotEmpty) 'body': section.body,
    if (section.entries.isNotEmpty)
      'entries': [
        for (final entry in section.entries)
          {'term': entry.term, 'definition': entry.definition},
      ],
    if (section.questions.isNotEmpty)
      'questions': [
        for (final question in section.questions)
          {
            'question': question.question,
            'options': [
              for (final option in question.options)
                {
                  'text': option.text,
                  if (option.why.isNotEmpty) 'why': option.why,
                },
            ],
            'answer': question.answer,
            if (question.explanation.isNotEmpty)
              'explanation': question.explanation,
          },
      ],
  };

  // --- Lectura tolerante ---------------------------------------------------

  /// El texto de una sección: un texto, una lista de párrafos, o viñetas
  /// sueltas en otro campo —todo junto, en ese orden—.
  static String _body(Map<String, Object?> json) {
    final parts = <String>[];
    final body = _pick(json, _bodyKeys);
    if (body is String) {
      parts.add(body.trim());
    } else if (body is List) {
      parts.add(
        [
          for (final p in body)
            if (_text(p, ReportLimits.body) case final t when t.isNotEmpty) t,
        ].join('\n\n'),
      );
    }
    final bullets = _pick(json, _bulletsKeys);
    if (bullets is List) {
      final lines = [
        for (final b in bullets)
          if (_text(b, ReportLimits.body) case final t when t.isNotEmpty)
            _asBullet(t),
      ];
      if (lines.isNotEmpty) parts.add(lines.join('\n'));
    }
    final joined = parts.where((p) => p.isNotEmpty).join('\n\n');
    return _clamp(joined.replaceAll('\r\n', '\n'), ReportLimits.body);
  }

  /// [line] como viñeta: con su «- » si no trae ya una marca.
  static String _asBullet(String line) =>
      line.startsWith(RegExp(r'[-*•]\s')) ? line : '- $line';

  static List<ReportEntry> _entries(Object? raw) {
    final entries = <ReportEntry>[];
    final seen = <String>{};
    void add(Object? term, Object? definition) {
      final t = _text(term, ReportLimits.term);
      if (t.isEmpty || !seen.add(foldStudyWord(t))) return;
      if (entries.length == ReportLimits.entries) return;
      entries.add(
        ReportEntry(
          term: t,
          definition: _text(definition, ReportLimits.definition),
        ),
      );
    }

    if (raw is Map) {
      for (final MapEntry(:key, :value) in raw.entries) {
        add(key, value);
      }
    } else if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          final e = _normalized(item);
          add(_pick(e, _termKeys), _pick(e, _definitionKeys));
        } else if (item is String) {
          // «Término: definición», como texto suelto.
          final match = RegExp(
            r'^\s*(?:\*\*)?(.+?)(?:\*\*)?\s*[:—–-]\s+(.+)$',
          ).firstMatch(item);
          if (match == null) {
            add(item, '');
          } else {
            add(match.group(1), match.group(2));
          }
        }
      }
    }
    return entries;
  }

  static bool _truthy(Object? value) =>
      value == true ||
      (value is String &&
          const {'true', 'si', 'sí', 'yes', '1'}.contains(value.toLowerCase()));

  /// El primero de [keys] que está en [json] y no es nulo.
  static Object? _pick(Map<String, Object?> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value != null) return value;
    }
    return null;
  }

  /// [raw] con las claves comparables: en minúsculas, sin tildes y sin
  /// guiones ni espacios —«palabras_clave», «palabrasClave» y «Palabras
  /// clave» son la misma—.
  static Map<String, Object?> _normalized(Map<dynamic, dynamic> raw) => {
    for (final MapEntry(:key, :value) in raw.entries)
      _normalizeKey('$key'): value,
  };

  static String _normalizeKey(String key) => foldStudyWord(
    key.replaceAllMapped(RegExp('([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}'),
  ).replaceAll(RegExp(r"[\s_\-']"), '');

  static String _text(Object? value, int max) {
    final String text;
    if (value is String) {
      text = value;
    } else if (value is num || value is bool) {
      text = '$value';
    } else {
      return '';
    }
    return _clamp(text.replaceAll(RegExp(r'\s+'), ' ').trim(), max);
  }

  /// [text] hasta [max] caracteres, cortado en la última palabra entera.
  static String _clamp(String text, int max) {
    if (text.length <= max) return text;
    final cut = text.substring(0, max - 1);
    final space = cut.lastIndexOf(RegExp(r'\s'));
    return '${(space > max ~/ 2 ? cut.substring(0, space) : cut).trimRight()}…';
  }

  // Las claves que se aceptan, ya normalizadas (`_normalizeKey`).
  static const _reportKeys = ['report', 'informe', 'document', 'documento'];
  static const _sectionsKeys = [
    'sections',
    'secciones',
    'seccion',
    'parts',
    'partes',
    'chapters',
    'capitulos',
  ];
  static const _titleKeys = [
    'title',
    'titulo',
    'heading',
    'encabezado',
    'name',
    'nombre',
    'letter',
    'letra',
  ];
  static const _subtitleKeys = [
    'subtitle',
    'subtitulo',
    'summary',
    'resumen',
    'description',
    'descripcion',
    'lead',
    'bajada',
  ];
  static const _bodyKeys = [
    'body',
    'text',
    'texto',
    'content',
    'contenido',
    'cuerpo',
    'markdown',
    'paragraphs',
    'parrafos',
  ];
  static const _bulletsKeys = [
    'bullets',
    'vinetas',
    'points',
    'puntos',
    'keypoints',
    'puntosclave',
    'items',
  ];
  static const _entriesKeys = [
    'entries',
    'terms',
    'terminos',
    'glossary',
    'glosario',
    'definitions',
    'definiciones',
  ];
  static const _termKeys = [
    'term',
    'termino',
    'word',
    'palabra',
    'concept',
    'concepto',
    'name',
    'nombre',
  ];
  static const _definitionKeys = [
    'definition',
    'definicion',
    'meaning',
    'significado',
    'description',
    'descripcion',
    'text',
    'texto',
  ];
  static const _questionsKeys = [
    'questions',
    'preguntas',
    'quiz',
    'cuestionario',
    'selftest',
    'autoevaluacion',
  ];
  static const _questionTextKeys = [
    'question',
    'pregunta',
    'enunciado',
    'prompt',
    'stem',
    'text',
    'texto',
  ];
  static const _optionsKeys = [
    'options',
    'opciones',
    'choices',
    'alternativas',
    'answers',
    'respuestas',
  ];
  static const _optionTextKeys = [
    'text',
    'texto',
    'option',
    'opcion',
    'label',
    'value',
    'valor',
  ];
  static const _whyKeys = [
    'why',
    'porque',
    'explanation',
    'explicacion',
    'feedback',
    'reason',
    'razon',
  ];
  static const _whyListKeys = [
    'whys',
    'optionexplanations',
    'explicaciones',
    'porques',
  ];
  static const _correctFlagKeys = [
    'correct',
    'correcta',
    'correcto',
    'iscorrect',
    'escorrecta',
  ];
  static const _answerKeys = [
    'answer',
    'respuesta',
    'answerindex',
    'correctindex',
    'correctanswer',
    'respuestacorrecta',
    'correct',
    'correcta',
  ];
  static const _explanationKeys = [
    'explanation',
    'explicacion',
    'why',
    'porque',
    'rationale',
    'justificacion',
  ];
  static const _keywordsKeys = [
    'keywords',
    'palabrasclave',
    'keyterms',
    'terminosclave',
  ];
}
