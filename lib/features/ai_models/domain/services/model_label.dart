/// Cómo se le muestra a la persona el modelo que hizo algo (F33): lo que
/// guarda una pasada de la IA (`ai_runs.model`) es el id del proveedor
/// —«gemini-3.8-flash», «claude-opus-5-5», «gpt-5.2-mini»— o la variante de
/// Gemma en el teléfono (`ChatModelOption.name`, «gemma4E4b»).
///
/// - «gemma4E4b» → «Gemma 4 E4B», como la nombra la pantalla del modelo;
/// - «gemini-3.8-flash» → «Gemini 3.8 Flash»;
/// - «claude-opus-5-5» → «Claude Opus 5.5» (sin la fecha de una versión
///   fijada, «-20260101»);
/// - «gpt-5.2-mini» → «GPT-5.2 mini», y la serie «o» tal cual, como los
///   escribe OpenAI;
/// - lo demás, como viene.
String modelLabel(String model) {
  final id = model.trim();
  final gemma = _gemmaLabels[id];
  if (gemma != null) return gemma;
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

/// Si [model] es Gemma en el teléfono, como lo guarda una pasada.
bool isLocalGemma(String model) => _gemmaLabels.containsKey(model.trim());

/// Las variantes de Gemma por su `ChatModelOption.name`, con el nombre que
/// les da la pantalla del modelo. Una variante nueva se agrega acá: la
/// prueba lo exige.
const _gemmaLabels = {
  'gemma4E4b': 'Gemma 4 E4B',
  'gemma3nE4b': 'Gemma 3n E4B',
  'gemma412b': 'Gemma 4 12B',
};
