import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';
import 'package:sinapsis/core/domain/entities/ai_changed_field.dart';
import 'package:sinapsis/core/domain/entities/ai_rejection_kind.dart';
import 'package:sinapsis/core/domain/entities/ai_run_scope.dart';

/// Una pasada de la IA sobre un elemento (F27): todo lo que aplicó sola en esa
/// vuelta —vínculos, tarjetas, propiedades— lleva su [id] en `ai_run_id`, y
/// por eso se puede deshacer entero, de un saque, sin tocar nada más.
///
/// Es el registro que «Lo que hizo la IA» muestra en orden de fecha. Lo que la
/// IA creó se cuenta al terminar ([relationsCreated] y compañía) y queda así:
/// es la historia. Lo que todavía sigue siendo de la IA se cuenta en vivo,
/// porque la persona pudo editar —adoptar— o borrar algo después.
///
/// Se va con su elemento. Viaja en la fusión de bóvedas, para que lo que llega
/// de otro dispositivo también se pueda deshacer acá.
@DataClassName('AiRunRow')
@TableIndex(name: 'idx_ai_runs_item', columns: {#itemId})
@TableIndex(name: 'idx_ai_runs_started', columns: {#startedAt})
class AiRuns extends Table {
  TextColumn get id => text()();

  /// El elemento que la IA organizó en esta pasada. Lo que creó puede tocar a
  /// otros —un vínculo une dos—, pero la pasada es de uno.
  TextColumn get itemId =>
      text().references(KnowledgeEntries, #id, onDelete: KeyAction.cascade)();

  /// Qué modelo trabajó, si se sabe: el mismo dato que una nota generada
  /// guarda en `generated_by_model`.
  TextColumn get model => text().nullable()();

  DateTimeColumn get startedAt => dateTime()();

  /// `null` mientras la pasada sigue, o si se cortó a mitad: lo que alcanzó a
  /// aplicar igual lleva su id y se deshace igual.
  DateTimeColumn get finishedAt => dateTime().nullable()();

  /// Cuándo la persona la deshizo entera. `null` = sigue en pie. Una pasada
  /// deshecha no se borra: queda para que la cola no vuelva a organizar sola
  /// un elemento que alguien ya le sacó a la IA.
  DateTimeColumn get undoneAt => dateTime().nullable()();

  /// Lo que creó, contado al terminar.
  IntColumn get relationsCreated => integer().withDefault(const Constant(0))();
  IntColumn get flashcardsCreated => integer().withDefault(const Constant(0))();
  IntColumn get propertiesCreated => integer().withDefault(const Constant(0))();

  /// La huella del texto que la pasada vio (`simhashOf`, la de los
  /// casi-duplicados de la decisión 40), en hexadecimal (v35). Con ella la
  /// cola sabe si una nota ya organizada cambió de verdad: dos textos del
  /// mismo largo y distinto contenido tienen huellas lejanas, y una coma de
  /// más casi no la mueve (`kNoteRegrowHammingBits`). `null` en las pasadas
  /// de antes de v35, que no la guardaban.
  ///
  /// Viaja con la pasada: una nota organizada en otro dispositivo también
  /// sabe cómo era cuando la IA la vio.
  TextColumn get contentSimhash => text().nullable()();

  /// Qué le pidieron a la pasada (v37): organizar el elemento o solo hacerle
  /// tarjetas (F30). Una de solo tarjetas se deshace y se lista como
  /// cualquiera, pero no cuenta como organizar el elemento: la cola lo sigue
  /// teniendo pendiente. Viaja con la pasada en la fusión de bóvedas.
  TextColumn get scope =>
      textEnum<AiRunScope>().withDefault(Constant(AiRunScope.organize.name))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Un dato del elemento que la IA completó en una pasada (F27, v35): el tema
/// de la biblioteca o un campo de la referencia, con el valor que tenía antes
/// y el que puso.
///
/// Los vínculos, las tarjetas y las propiedades son filas propias y llevan su
/// pasada en `ai_run_id`; el tema y la referencia son columnas del elemento,
/// que no tienen dónde llevarla. Esta tabla es esa marca: lo que permite que
/// deshacer la pasada devuelva el elemento a como estaba —el tema anterior,
/// el campo vacío— **solo si sigue con lo que puso la IA**. Si la persona lo
/// cambió después, ya es suyo, y deshacer no lo toca.
///
/// Es la historia: no se borra al deshacer. Lo que la pasada completó es
/// cuántas filas tiene; lo que todavía es de la IA se mira contra el valor
/// de hoy. Se va con su pasada, y viaja con ella en la fusión de bóvedas.
@DataClassName('AiFieldChangeRow')
@TableIndex(name: 'idx_ai_field_changes_run', columns: {#aiRunId})
class AiFieldChanges extends Table {
  TextColumn get id => text()();

  /// La pasada que lo completó. El elemento es el de la pasada.
  TextColumn get aiRunId =>
      text().references(AiRuns, #id, onDelete: KeyAction.cascade)();

  TextColumn get field => textEnum<AiChangedField>()();

  /// Lo que había antes, como texto (`AiFieldValues`); `null` si estaba
  /// vacío.
  TextColumn get beforeValue => text().nullable()();

  /// Lo que puso la IA, como texto (`AiFieldValues`). Si el valor de hoy es
  /// otro, lo cambió la persona.
  TextColumn get afterValue => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Lo que la persona dijo que «no era» (F27): la memoria que impide que la IA
/// vuelva a proponer lo mismo —el mismo vínculo, la misma propiedad en el
/// mismo elemento, la misma pregunta—.
///
/// Es una tabla propia y no `Suggestions` con estado `rejected`, aunque se
/// parezcan, por tres motivos:
///
/// - `Suggestions` es una cola de revisión y su `rejected` ya significa varias
///   cosas —descartada en la Bandeja, reemplazada por otra más nueva (los
///   datos de una referencia)—; mezclar ahí un «no lo vuelvas a hacer» haría
///   que cualquier limpieza de la cola borrara la memoria.
/// - Saber si algo se rechazó tiene que ser una consulta por clave, no leer el
///   JSON de cada propuesta: acá es [fingerprint], con su índice único.
/// - Un vínculo tiene dos extremos y la memoria tiene que irse con cualquiera
///   de los dos ([otherItemId] también es `CASCADE`); `Suggestions` cuelga de
///   uno solo.
///
/// Viaja en la fusión de bóvedas: es lo único que hace de lápida para lo que
/// la IA hizo, y sin ella una copia vieja devolvería lo que se descartó.
@DataClassName('AiRejectionRow')
class AiRejections extends Table {
  TextColumn get id => text()();

  TextColumn get kind => textEnum<AiRejectionKind>()();

  /// El elemento al que se refiere. En un vínculo, el menor de los dos ids:
  /// así el par se guarda igual mire desde donde se mire.
  TextColumn get itemId =>
      text().references(KnowledgeEntries, #id, onDelete: KeyAction.cascade)();

  /// Solo en un vínculo: el otro extremo, el mayor de los dos ids.
  TextColumn get otherItemId => text().nullable().references(
    KnowledgeEntries,
    #id,
    onDelete: KeyAction.cascade,
  )();

  /// Qué se rechazó, normalizado, dentro de [kind] e [itemId]: el otro
  /// extremo y el tipo de un vínculo, la categoría y el valor de una
  /// propiedad, la pregunta de una tarjeta. Ver `ai_rejection_memory.dart`.
  TextColumn get fingerprint => text()();

  /// El id de lo que se borró —el vínculo, la tarjeta, el valor de la
  /// propiedad—, sin clave foránea porque ya no existe. Con él una fusión
  /// reconoce la MISMA fila que vuelve de una copia vieja, aunque su texto no
  /// se pueda normalizar en SQL.
  TextColumn get subjectId => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    // Lo mismo se recuerda una sola vez.
    'UNIQUE (kind, item_id, fingerprint)',
  ];
}
