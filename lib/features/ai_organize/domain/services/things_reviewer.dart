import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/entities/correction_subject.dart';

/// Algo que hizo la IA en un elemento, como se le da a revisar a otro modelo
/// (F33): todo lo que no es una tarjeta. Lo arma `ReviewThingsStep` a partir
/// de `ReviewableAiThing`, con las palabras que entiende el modelo.
@immutable
class ThingToReview {
  const ThingToReview({
    required this.subject,
    required this.name,
    required this.value,
    this.note,
    this.options = const [],
    this.canFix = true,
    this.canRemove = true,
    this.context = '',
  });

  final CorrectionSubject subject;

  /// Qué es, en una línea: «vínculo con «Cortázar»», «etiqueta de «Tema»»,
  /// «Editorial».
  final String name;

  /// Lo que puso la IA: en un vínculo, su tipo (la palabra del pedido).
  final String value;

  /// En un vínculo, la frase que dice por qué; `null` en lo demás.
  final String? note;

  /// Lo único que vale al corregirlo; vacío si es un texto libre.
  final List<String> options;

  final bool canFix;
  final bool canRemove;

  /// Lo que el modelo necesita ver además del elemento: el comienzo del otro
  /// elemento de un vínculo, los títulos que reúne una nota mapa.
  final String context;
}

/// Lo que el revisor dice de algo que está mal (F33). Lo que está bien no trae
/// veredicto.
@immutable
sealed class ThingVerdict {
  const ThingVerdict({required this.index, required this.reason});

  /// Cuál de las cosas que se le dieron, desde 0.
  final int index;

  /// Por qué, en una línea del modelo.
  final String reason;
}

/// Corregirlo: el valor como debería quedar —una de las opciones, si las
/// hay—; en un vínculo, el tipo y la frase.
final class ThingCorrection extends ThingVerdict {
  const ThingCorrection({
    required super.index,
    required super.reason,
    required this.value,
    this.note,
  });

  final String value;
  final String? note;

  @override
  bool operator ==(Object other) =>
      other is ThingCorrection &&
      other.index == index &&
      other.reason == reason &&
      other.value == value &&
      other.note == note;

  @override
  int get hashCode => Object.hash(index, reason, value, note);

  @override
  String toString() => 'ThingCorrection($index, $value | $note; $reason)';
}

/// Sacarlo: no corresponde.
final class ThingRemoval extends ThingVerdict {
  const ThingRemoval({required super.index, required super.reason});

  @override
  bool operator ==(Object other) =>
      other is ThingRemoval && other.index == index && other.reason == reason;

  @override
  int get hashCode => Object.hash(index, reason);

  @override
  String toString() => 'ThingRemoval($index; $reason)';
}

/// Revisa lo que hizo la IA en un elemento que no son tarjetas, con el modelo
/// de lenguaje elegido (F33, «Revisar con otro modelo»): dice qué corregir —y
/// cómo— y qué sacar. Nunca agrega nada y nunca guarda nada.
// ignore: one_member_abstracts
abstract interface class ThingsReviewer {
  /// Los veredictos sobre [things] del elemento [itemTitle], que se ve por
  /// [itemExcerpt]; solo de lo que está mal. Lista vacía si está todo bien, o
  /// si el modelo no contestó nada que se pudiera leer.
  Future<List<ThingVerdict>> reviewThings({
    required String itemTitle,
    required String itemExcerpt,
    required List<ThingToReview> things,
  });
}
