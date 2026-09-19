import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/items.dart';

/// Un `[[Título]]` escrito dentro de una nota, con el elemento al que apunta
/// si ya existe.
///
/// Sin esta tabla, un enlace roto no deja rastro: los `[[ ]]` solo se
/// resolvían al guardar, y un título sin destino quedaba escrito en el texto y
/// en ningún otro lado. Persistirlos vuelve consultables los enlaces rotos de
/// toda la bóveda sin volver a leer el texto de cada nota.
///
/// La `Relation` `relatedTo` que alimenta el grafo sigue siendo la fuente de
/// verdad de "estos dos están vinculados"; esto es el registro de lo que el
/// texto dice.
///
/// Referencia a `Items`, no al espejo nuevo, igual que `Relations`: F10 las
/// repunta juntas.
@DataClassName('InlineLinkRow')
@TableIndex(name: 'idx_inline_link_target', columns: {#toItemId})
@TableIndex(name: 'idx_inline_link_title', columns: {#normalizedTitle})
class InlineLinks extends Table {
  @override
  String get tableName => 'inline_link';

  TextColumn get id => text()();

  /// La nota que contiene el enlace. Si se borra, sus enlaces se van con ella.
  TextColumn get fromItemId =>
      text().references(Items, #id, onDelete: KeyAction.cascade)();

  /// El título como se escribió entre corchetes, recortado: con él se crea la
  /// nota que falta.
  TextColumn get targetTitle => text()();

  /// El título para comparar: recortado y en minúsculas.
  TextColumn get normalizedTitle => text()();

  /// El elemento al que apunta, o `null` si el enlace está ROTO. Si ese
  /// elemento se borra, el enlace vuelve a quedar roto —no desaparece—: el
  /// texto de la nota sigue diciendo `[[Título]]`.
  TextColumn get toItemId =>
      text().nullable().references(Items, #id, onDelete: KeyAction.setNull)();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    // El mismo destino escrito dos veces en una nota es un solo enlace.
    'UNIQUE (from_item_id, normalized_title)',
  ];
}
