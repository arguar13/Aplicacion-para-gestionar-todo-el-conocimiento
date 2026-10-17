/// Cómo se le muestra a la persona el modelo que hizo algo (F33): lo que
/// guarda una pasada de la IA (`ai_runs.model`) es el id del proveedor
/// —«gemini-3.8-flash», «claude-opus-5-5», «gpt-5.2-mini»— o el nombre de
/// Gemma, que ya es para leer.
///
/// - «gemini-3.8-flash» → «Gemini 3.8 Flash»;
/// - «claude-opus-5-5» → «Claude Opus 5.5» (sin la fecha de una versión
///   fijada, «-20260101»);
/// - «gpt-5.2-mini» → «GPT-5.2 mini», y la serie «o» tal cual, como los
///   escribe OpenAI;
/// - lo demás, como viene.
String modelLabel(String model) {
  final id = model.trim();
  if (id.startsWith('gemini-')) {
    return id.split('-').map(_capitalized).join(' ');
  }
  if (id.startsWith('claude-')) {
    final parts = id
        .split('-')
        .where((part) => !RegExp(r'^\d{8}$').hasMatch(part))
        .toList();
    final words = <String>[];
    final version = <String>[];
    for (final part in parts) {
      if (RegExp(r'^\d+$').hasMatch(part)) {
        version.add(part);
      } else {
        if (version.isNotEmpty) words.add(version.join('.'));
        version.clear();
        words.add(_capitalized(part));
      }
    }
    if (version.isNotEmpty) words.add(version.join('.'));
    return words.join(' ');
  }
  if (id.startsWith('gpt-')) {
    final rest = id.substring(4);
    final dash = rest.indexOf('-');
    if (dash < 0) return 'GPT-$rest';
    return 'GPT-${rest.substring(0, dash)} '
        '${rest.substring(dash + 1).replaceAll('-', ' ')}';
  }
  return id;
}

String _capitalized(String word) =>
    word.isEmpty ? word : word[0].toUpperCase() + word.substring(1);
