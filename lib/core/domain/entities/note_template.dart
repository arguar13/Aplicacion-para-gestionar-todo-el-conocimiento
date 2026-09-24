import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';

/// Una propiedad que una plantilla precarga: la categoría y el valor, ya
/// resueltos —no solo sus `id`— para mostrarla sin volver a consultar la
/// base (F16).
///
/// Al aplicar la plantilla se asigna por [value] —el mismo camino que
/// escribir a mano en `PropertyEditor`, que crea el valor si hace falta—,
/// no por un `valueId` guardado: un valor que alguien borró o fusionó
/// después no deja a la plantilla con una referencia colgando, y uno
/// renombrado sigue resolviendo al mismo lugar.
@immutable
class TemplateProperty {
  const TemplateProperty({
    required this.definitionId,
    required this.definitionName,
    required this.value,
  });

  final String definitionId;
  final String definitionName;
  final String value;

  @override
  bool operator ==(Object other) =>
      other is TemplateProperty &&
      other.definitionId == definitionId &&
      other.definitionName == definitionName &&
      other.value == value;

  @override
  int get hashCode => Object.hash(definitionId, definitionName, value);
}

/// Una plantilla de nota: su estructura de bloques y sus propiedades, ya
/// puestas, para no armarlas de cero cada vez (F16).
@immutable
class NoteTemplate {
  const NoteTemplate({
    required this.id,
    required this.name,
    required this.blocks,
    required this.properties,
    required this.createdAt,
  });

  final String id;
  final String name;
  final List<ContentBlock> blocks;
  final List<TemplateProperty> properties;
  final DateTime createdAt;
}
