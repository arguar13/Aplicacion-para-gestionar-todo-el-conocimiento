import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/note_template.dart';

/// Las plantillas de nota (F16): su estructura de bloques y sus propiedades.
abstract interface class NoteTemplateRepository {
  /// Todas, por nombre, emitiendo de nuevo cada vez que algo cambia.
  Stream<List<NoteTemplate>> watchAll();

  Future<NoteTemplate> create({
    required String name,
    required List<ContentBlock> blocks,
    required List<TemplateProperty> properties,
  });

  Future<void> rename(String id, String name);

  Future<void> delete(String id);
}
