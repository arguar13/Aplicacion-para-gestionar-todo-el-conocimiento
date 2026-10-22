import 'package:sinapsis/features/ai_models/domain/services/model_label.dart';

/// Si [next] es más capaz que [previous] (F33, decisión D): lo que decide si
/// al cambiar de modelo se ofrece revisar lo que hizo el anterior. Los dos
/// como los guarda una pasada (`ai_runs.model`); [previous] `null` es una
/// pasada de antes de que se anotara el modelo, que solo podía ser Gemma.
///
/// - Uno en la nube es más capaz que Gemma en el teléfono.
/// - Entre dos del mismo proveedor, el más grande: Gemma 4 12B sobre los
///   E4B; en Gemini, Pro sobre Flash y Flash sobre Flash Lite; en Claude,
///   Opus (o Fable) sobre Sonnet y Sonnet sobre Haiku; en OpenAI, el entero
///   sobre mini y mini sobre nano.
///
/// Entre proveedores distintos de la nube, o con un modelo que no se
/// conoce, no se sabe: no es más capaz, y no se ofrece nada (queda el
/// botón).
bool isMoreCapableModel({required String? previous, required String next}) {
  final before = _rankOf(previous);
  final after = _rankOf(next);
  if (before == null || after == null) return false;
  if (before.family == _Family.gemma) {
    if (after.family != _Family.gemma) return true;
  } else if (after.family != before.family) {
    return false;
  }
  final (sizeBefore, sizeAfter) = (before.size, after.size);
  return sizeBefore != null && sizeAfter != null && sizeAfter > sizeBefore;
}

enum _Family { gemma, gemini, claude, openAi }

/// La familia de un modelo y su tamaño dentro de ella (`null` si no se
/// sabe).
typedef _Rank = ({_Family family, int? size});

_Rank? _rankOf(String? model) {
  if (model == null) return (family: _Family.gemma, size: null);
  final id = model.trim().toLowerCase();
  if (isLocalGemma(model)) {
    return (family: _Family.gemma, size: id.endsWith('12b') ? 1 : 0);
  }
  if (id.startsWith('gemini-')) {
    final size = id.contains('flash-lite')
        ? 0
        : id.contains('flash')
        ? 1
        : id.contains('pro')
        ? 2
        : null;
    return (family: _Family.gemini, size: size);
  }
  if (id.startsWith('claude-')) {
    final size = id.contains('haiku')
        ? 0
        : id.contains('sonnet')
        ? 1
        : id.contains('opus') || id.contains('fable')
        ? 2
        : null;
    return (family: _Family.claude, size: size);
  }
  if (id.startsWith('gpt-') || RegExp(r'^o\d').hasMatch(id)) {
    final size = id.contains('nano')
        ? 0
        : id.contains('mini')
        ? 1
        : 2;
    return (family: _Family.openAi, size: size);
  }
  return null;
}
