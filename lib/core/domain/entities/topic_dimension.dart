import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';

/// El identificador de la dimensión «Temas» del Mapa y el Atlas (F28).
///
/// Las dos pantallas piden su dimensión con un identificador: el de la
/// categoría, o este para los temas. No es el de ninguna fila —las categorías
/// se identifican con UUID—, así que no hay choque posible, y todo lo que ya
/// viaja con el id de una categoría —el pedido del mapa, su caché, sus
/// recuerdos de comunidades, el Atlas por categoría— sirve igual para los
/// temas.
const kSpacesDimensionId = '@temas';

/// Si [dimensionId] es el de los temas.
bool isSpacesDimension(String dimensionId) => dimensionId == kSpacesDimensionId;

/// Por qué agrupan el Mapa y el Atlas (F28): los **temas** —los espacios, lo
/// que se elige al guardar: planos, uno por elemento— o una categoría de
/// propiedades de texto, como las **etiquetas** —la categoría de sistema que
/// en la base se llama «Tema»—, con su jerarquía.
@immutable
class TopicDimension {
  /// Los temas: los espacios.
  const TopicDimension.spaces() : category = null;

  /// Una categoría de texto.
  const TopicDimension.category(PropertyDefinition this.category);

  /// La categoría, o `null` para los temas.
  final PropertyDefinition? category;

  /// Con qué se le pide al Mapa o al Atlas: [kSpacesDimensionId] o el id de
  /// la categoría.
  String get id => category?.id ?? kSpacesDimensionId;

  bool get isSpaces => category == null;

  /// Si es la categoría de las etiquetas.
  bool get isTags => category?.isTema ?? false;

  @override
  bool operator ==(Object other) => other is TopicDimension && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Las dimensiones que ofrecen el Mapa y el Atlas —los temas, las etiquetas y
/// las demás categorías de texto, en ese orden— y la que se muestra: la de
/// [chosenId] si existe; si no, los temas cuando [hasSpaces], o las
/// etiquetas, o los temas igual.
///
/// Los temas se ofrecen siempre, aunque no haya ninguno: mirarlos dice cuántos
/// elementos no tienen y ofrece organizarlos. Solo las categorías de texto
/// tienen jerarquía: las demás no arman un árbol.
({List<TopicDimension> options, TopicDimension selected}) topicDimensionsOf(
  List<PropertyDefinition> definitions, {
  required bool hasSpaces,
  String? chosenId,
}) {
  final text = [
    for (final d in definitions)
      if (d.type == PropertyValueType.text) d,
  ];
  final options = [
    const TopicDimension.spaces(),
    for (final d in text)
      if (d.isTema) TopicDimension.category(d),
    for (final d in text)
      if (!d.isTema) TopicDimension.category(d),
  ];
  TopicDimension? byId(String id) {
    for (final option in options) {
      if (option.id == id) return option;
    }
    return null;
  }

  final chosen = chosenId == null ? null : byId(chosenId);
  final tags = options.where((o) => o.isTags).firstOrNull;
  return (
    options: options,
    selected: chosen ?? (hasSpaces ? options.first : tags ?? options.first),
  );
}
