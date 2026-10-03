import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/ai_certainty.dart';

/// Bajo qué tema del árbol va un tema suelto, según el modelo (F27, el Atlas).
@immutable
class TopicParentChoice {
  const TopicParentChoice({required this.index, this.certainty});

  /// La posición del padre elegido en la lista que se le dio al modelo.
  final int index;

  /// Qué tan seguro dijo estar; `null` si no lo dijo.
  final AiCertainty? certainty;

  @override
  bool operator ==(Object other) =>
      other is TopicParentChoice &&
      other.index == index &&
      other.certainty == certainty;

  @override
  int get hashCode => Object.hash(index, certainty);

  @override
  String toString() => 'TopicParentChoice($index, $certainty)';
}

/// Elige bajo cuál de [candidates] —temas que ya están en el árbol, cada uno
/// escrito con su camino: «Historia › Historia antigua»— va el tema [topic],
/// que apareció en el elemento [itemTitle] (F27). Con el mismo modelo de
/// lenguaje del chat —`GemmaChatModel.chooseTopicParent`—. `null` si bajo
/// ninguno, o si el modelo no contestó nada que se pueda leer.
///
/// Nunca propone un tema nuevo: elige entre los que la persona ya tiene. Una
/// función y no una interfaz, como `SpaceChooser`: el doble de una prueba es
/// una función.
typedef TopicParentChooser =
    Future<TopicParentChoice?> Function({
      required String topic,
      required String itemTitle,
      required List<String> candidates,
    });

final _choiceLine = RegExp(
  r'^PADRE:\s*(\S+?)\s*(?:\|\s*(\w+))?\s*$',
  caseSensitive: false,
);

/// Lee la respuesta del modelo: `PADRE: <número> | <certeza>` o `PADRE:
/// ninguno`. Función pura, como `parseSpaceChoice`: la primera línea que se
/// entiende vale, y un número fuera de la lista es lo mismo que ninguno
/// —nunca se adivina cuál quiso decir—.
TopicParentChoice? parseTopicParentChoice(
  String raw, {
  required int candidateCount,
}) {
  for (final rawLine in raw.split('\n')) {
    final match = _choiceLine.firstMatch(rawLine.trim());
    if (match == null) continue;
    final number = int.tryParse(match.group(1)!);
    if (number == null || number < 1 || number > candidateCount) return null;
    final certainty = match.group(2);
    return TopicParentChoice(
      index: number - 1,
      certainty: certainty == null ? null : AiCertainty.parse(certainty),
    );
  }
  return null;
}
