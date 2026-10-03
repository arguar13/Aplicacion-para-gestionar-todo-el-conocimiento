import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/ai_certainty.dart';

/// En qué tema de la biblioteca (un espacio) va un elemento, según el modelo.
@immutable
class SpaceChoice {
  const SpaceChoice({required this.index, this.certainty});

  /// La posición del tema elegido en la lista que se le dio al modelo.
  final int index;

  /// Qué tan seguro dijo estar; `null` si no lo dijo.
  final AiCertainty? certainty;

  @override
  bool operator ==(Object other) =>
      other is SpaceChoice &&
      other.index == index &&
      other.certainty == certainty;

  @override
  int get hashCode => Object.hash(index, certainty);

  @override
  String toString() => 'SpaceChoice($index, $certainty)';
}

/// Elige en cuál de los temas que ya existen (`spaces`) va un elemento (F27),
/// con el mismo modelo de lenguaje del chat —`GemmaChatModel.chooseSpace`—.
/// `null` si en ninguno, o si el modelo no contestó nada que se pueda leer.
/// Nunca propone un tema nuevo: los temas los arma la persona.
///
/// Una función y no una interfaz de un solo método: es una sola tarea, y así
/// el doble de una prueba es una función.
typedef SpaceChooser =
    Future<SpaceChoice?> Function({
      required String itemTitle,
      required String excerpt,
      required List<String> spaces,
    });

final _choiceLine = RegExp(
  r'^TEMA:\s*(\S+?)\s*(?:\|\s*(\w+))?\s*$',
  caseSensitive: false,
);

/// Lee la respuesta del modelo: `TEMA: <número> | <certeza>` o `TEMA:
/// ninguno`. Función pura, como `parseRelationSuggestions`: lo que puede
/// fallar es el formato de un texto, y se prueba sin modelo. La primera
/// línea que se entiende vale; un número fuera de la lista es lo mismo que
/// ninguno —nunca se adivina cuál quiso decir—.
SpaceChoice? parseSpaceChoice(String raw, {required int spaceCount}) {
  for (final rawLine in raw.split('\n')) {
    final match = _choiceLine.firstMatch(rawLine.trim());
    if (match == null) continue;
    final number = int.tryParse(match.group(1)!);
    if (number == null || number < 1 || number > spaceCount) return null;
    final certainty = match.group(2);
    return SpaceChoice(
      index: number - 1,
      certainty: certainty == null ? null : AiCertainty.parse(certainty),
    );
  }
  return null;
}
