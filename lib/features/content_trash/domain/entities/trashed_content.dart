import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/entities/trashed_content_kind.dart';

/// Cuánto espera algo en la papelera del contenido antes de borrarse de
/// verdad (F30, decisión 68): lo mismo que se le dijo a la persona al
/// soltarlo.
const kContentTrashRetention = Duration(days: 30);

/// Lo que se soltó de un elemento —su archivo original o su texto— y espera
/// en la papelera del contenido (F30, decisión 68), tal como se muestra en el
/// detalle: qué es, cuánto ocupa y hasta cuándo se puede recuperar.
@immutable
class TrashedContent {
  const TrashedContent({
    required this.id,
    required this.itemId,
    required this.kind,
    required this.trashedAt,
    this.sizeBytes,
    this.textLength,
  });

  final String id;
  final String itemId;
  final TrashedContentKind kind;

  /// Cuándo se soltó.
  final DateTime trashedAt;

  /// Cuánto pesa el archivo, si se pudo medir. Solo en un archivo.
  final int? sizeBytes;

  /// Cuántos caracteres tiene el texto. Solo en un texto.
  final int? textLength;

  /// Desde cuándo ya no se puede recuperar: el barrido lo borra de verdad.
  DateTime get expiresAt => trashedAt.add(kContentTrashRetention);

  @override
  bool operator ==(Object other) =>
      other is TrashedContent &&
      other.id == id &&
      other.itemId == itemId &&
      other.kind == kind &&
      other.trashedAt == trashedAt &&
      other.sizeBytes == sizeBytes &&
      other.textLength == textLength;

  @override
  int get hashCode =>
      Object.hash(id, itemId, kind, trashedAt, sizeBytes, textLength);
}

/// Cómo terminó «Recuperar» algo de la papelera del contenido.
enum ContentRestoreOutcome {
  /// Volvió al elemento, como estaba.
  restored,

  /// El archivo ya no estaba en el teléfono —alguien vació el almacenamiento
  /// de la app—: no hay nada que recuperar, y sale de la papelera.
  fileMissing,

  /// El elemento ya tiene otro archivo original: recuperar el viejo lo
  /// dejaría sin lugar. Queda en la papelera.
  alreadyHasFile,

  /// Ya no estaba en la papelera: se recuperó o se venció mientras tanto.
  gone,
}
