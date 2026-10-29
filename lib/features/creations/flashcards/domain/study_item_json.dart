/// Leer con tolerancia lo que devuelve la IA —y lo guardado— en los mazos y
/// los cuestionarios de «Lo creado» (F43, paso 8): las claves pueden venir en
/// castellano o en inglés, en camelCase, snake_case o con tildes
/// («explicación», `correctAnswer`, `document_id`), y los valores como texto,
/// número o booleano escrito de varias maneras. Nada falla por un campo: lo
/// que no se entiende queda vacío.
library;

import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';

/// Una clave reducida a lo que se compara: sin mayúsculas, tildes, guiones
/// ni espacios. `correct_answer`, `correctAnswer` y «Correct answer» son la
/// misma.
String studyJsonKey(String key) =>
    normalizeVocabularyLabel(key).replaceAll(RegExp('[^a-z0-9]'), '');

/// [raw] con sus claves reducidas ([studyJsonKey]); `null` si no es un
/// objeto.
Map<String, Object?>? studyJsonObject(Object? raw) {
  if (raw is! Map) return null;
  return {
    for (final entry in raw.entries)
      if (entry.key is String) studyJsonKey(entry.key as String): entry.value,
  };
}

/// El primero de [keys] que está en [json] —ya reducido—, o `null`.
Object? studyJsonPick(Map<String, Object?> json, List<String> keys) {
  for (final key in keys) {
    final value = json[studyJsonKey(key)];
    if (value != null) return value;
  }
  return null;
}

/// Un texto de [json] con una de [keys]: recortado y con los espacios de más
/// juntados; un número también vale. Vacío si no hay. Nunca más de [max]
/// caracteres: se corta en la última palabra entera, con «…».
String studyJsonText(
  Map<String, Object?> json,
  List<String> keys, {
  int max = 2000,
}) {
  final value = studyJsonPick(json, keys);
  final text = switch (value) {
    final String s => s,
    final num n => '$n',
    final bool b => '$b',
    _ => '',
  };
  return clampStudyText(text, max);
}

/// [text] sin espacios de más y, si pasa de [max], cortado en la última
/// palabra entera con «…».
String clampStudyText(String text, int max) {
  final clean = text
      .replaceAll('\r\n', '\n')
      .split('\n')
      .map((line) => line.trim().replaceAll(RegExp(r'[ \t]+'), ' '))
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
  if (clean.length <= max) return clean;
  final cut = clean.substring(0, max);
  final space = cut.lastIndexOf(' ');
  return '${(space > max ~/ 2 ? cut.substring(0, space) : cut).trimRight()}…';
}

/// Un sí o no de [json] con una de [keys]: `true`, `"sí"`, `"true"`, `1`,
/// `"correcta"`… `null` si no dice.
bool? studyJsonBool(Map<String, Object?> json, List<String> keys) {
  final value = studyJsonPick(json, keys);
  return switch (value) {
    final bool b => b,
    final num n => n != 0,
    final String s => switch (studyJsonKey(s)) {
      'true' ||
      'si' ||
      'yes' ||
      'verdadero' ||
      'correcta' ||
      'correcto' => true,
      'false' || 'no' || 'falso' || 'incorrecta' || 'incorrecto' => false,
      _ => null,
    },
    _ => null,
  };
}

/// Una lista de [json] con una de [keys]; vacía si no hay. Un solo valor
/// suelto cuenta como una lista de uno.
List<Object?> studyJsonList(Map<String, Object?> json, List<String> keys) {
  final value = studyJsonPick(json, keys);
  if (value == null) return const [];
  return value is List ? value : [value];
}

/// Los textos de una lista de [json] con una de [keys], sin vacíos ni
/// repetidos.
List<String> studyJsonTexts(
  Map<String, Object?> json,
  List<String> keys, {
  int max = 400,
}) {
  final seen = <String>{};
  return [
    for (final raw in studyJsonList(json, keys))
      if (raw is String || raw is num)
        if (clampStudyText('$raw', max) case final text
            when text.isNotEmpty && seen.add(normalizeVocabularyLabel(text)))
          text,
  ];
}
