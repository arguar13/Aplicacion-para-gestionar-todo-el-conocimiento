import 'package:meta/meta.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';

/// El recorte de Procesado sobre el que trabaja Repasar (F43, decisión D): lo
/// que se elige en el selector de arriba, y lo que manda en toda la pantalla
/// —«Para hoy» cuenta lo suyo, las tarjetas de crear trabajan sobre él y «Lo
/// creado» muestra lo suyo—.
///
/// **Todo sale de Procesado**, nunca de la Biblioteca:
///
/// - [AllProcessed]: todo lo procesado;
/// - [ProcessedDocumentScope]: un documento procesado;
/// - [NotebookScope]: un cuaderno, que desde F41 solo guarda procesados;
/// - [TopicScope]: un tema del Atlas por categoría —un valor del vocabulario,
///   con todas sus ramas, como el Atlas—;
/// - [SpaceScope]: un tema del Atlas por «Temas» —un espacio de F37, plano—.
///
/// Es un criterio que se evalúa al usarlo, como `StudyScope`: un documento que
/// entra hoy en un cuaderno entra solo en su recorte.
///
/// Se guarda como texto ([storageKey]): `all`, `document:<id>`,
/// `notebook:<id>`, `topic:<id>` o `space:<id>`. [CreationScope.parse] lo
/// lee; una clave que no se entiende da `null`, nunca un recorte inventado.
@immutable
sealed class CreationScope {
  const CreationScope();

  /// Lo procesado entero: «Todo lo procesado».
  const factory CreationScope.allProcessed() = AllProcessed;

  /// Un documento procesado.
  const factory CreationScope.document(String documentId) =
      ProcessedDocumentScope;

  /// Un cuaderno.
  const factory CreationScope.notebook(String notebookId) = NotebookScope;

  /// Un valor del vocabulario con todas sus ramas.
  const factory CreationScope.topic(String valueId) = TopicScope;

  /// Un tema de F37 (un espacio).
  const factory CreationScope.space(String spaceId) = SpaceScope;

  /// La clase del recorte, como se guarda en `study_creations.scope_kind`.
  String get kindKey;

  /// El id de lo que apunta; `null` en [AllProcessed].
  String? get id;

  /// La clave estable: [kindKey], y `:` con el [id] si lo tiene.
  String get storageKey => id == null ? kindKey : '$kindKey:$id';

  /// Si no recorta nada.
  bool get isAll => this is AllProcessed;

  /// Lo que cuenta «Para hoy» para este recorte (decisión B): todo con
  /// [AllProcessed] —«Todo» es todo, también las tarjetas que la Biblioteca ya
  /// tenía, para que no se pierda ninguna—; y si no, un recorte de estudio de
  /// lo procesado, que suma a las tarjetas de cada documento las de su fuente
  /// —las que el documento muestra en «De la fuente»—.
  StudyScope get studyScope =>
      isAll ? const StudyScope.all() : StudyScope.processed(storageKey);

  /// El recorte de [key], o `null` si no se entiende.
  static CreationScope? parse(String key) {
    if (key == AllProcessed.key) return const AllProcessed();
    final colon = key.indexOf(':');
    if (colon <= 0 || colon == key.length - 1) return null;
    return fromParts(key.substring(0, colon), key.substring(colon + 1));
  }

  /// El recorte de su clase [kindKey] y su [id], como se guardan en dos
  /// columnas; `null` si no se entiende.
  static CreationScope? fromParts(String kindKey, String? id) {
    if (kindKey == AllProcessed.key) {
      return id == null ? const AllProcessed() : null;
    }
    if (id == null || id.isEmpty) return null;
    return switch (kindKey) {
      ProcessedDocumentScope.key => ProcessedDocumentScope(id),
      NotebookScope.key => NotebookScope(id),
      TopicScope.key => TopicScope(id),
      SpaceScope.key => SpaceScope(id),
      _ => null,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is CreationScope && other.storageKey == storageKey;

  @override
  int get hashCode => storageKey.hashCode;

  @override
  String toString() => 'CreationScope($storageKey)';
}

/// Lo procesado entero: «Todo lo procesado».
final class AllProcessed extends CreationScope {
  const AllProcessed();

  static const key = 'all';

  @override
  String get kindKey => key;

  @override
  String? get id => null;
}

/// Un documento procesado.
final class ProcessedDocumentScope extends CreationScope {
  const ProcessedDocumentScope(this.documentId);

  static const key = 'document';

  final String documentId;

  @override
  String get kindKey => key;

  @override
  String get id => documentId;
}

/// Un cuaderno: los procesados que tiene hoy, manuales o por consulta.
final class NotebookScope extends CreationScope {
  const NotebookScope(this.notebookId);

  static const key = 'notebook';

  final String notebookId;

  @override
  String get kindKey => key;

  @override
  String get id => notebookId;
}

/// Un valor del vocabulario CON todas sus ramas: «Roma» trae lo procesado
/// asignado a «Roma republicana», como el Atlas por categoría.
final class TopicScope extends CreationScope {
  const TopicScope(this.valueId);

  static const key = 'topic';

  final String valueId;

  @override
  String get kindKey => key;

  @override
  String get id => valueId;
}

/// Un tema de F37 —un espacio—, como el Atlas por «Temas»: los temas no tienen
/// subtemas.
final class SpaceScope extends CreationScope {
  const SpaceScope(this.spaceId);

  static const key = 'space';

  final String spaceId;

  @override
  String get kindKey => key;

  @override
  String get id => spaceId;
}
