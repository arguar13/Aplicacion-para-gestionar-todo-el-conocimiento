import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/ai_runs.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';
import 'package:sinapsis/core/database/tables/renditions.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';

/// Un hecho fechado dentro de un documento (F40, v44): «1859: publica *El
/// origen de las especies*», con la fecha, de qué parte del texto sale y
/// quién lo puso.
///
/// «Fecha del hecho» (`property_values`) es la fecha del elemento ENTERO —una
/// carta de 1810—, compartida por todos los que usan el mismo valor y sin
/// saber qué pasó en ella. Esto es una fecha DENTRO de un elemento: un libro
/// cuenta muchos hechos, cada uno con su título y su cita. Las dos conviven
/// en la línea de tiempo (decisión C de F40) y no se migra nada de una a otra.
///
/// - **La fecha** tiene la forma de `property_values`: el año astronómico
///   firmado (1 a.C. = 0, 44 a.C. = -43), el mes y el día del PRIMER día que
///   cubre —1 y 1 para lo que no los usa—, la precisión y el «circa». A
///   diferencia de ahí, el fin no es un derivado de la precisión sino una
///   segunda fecha opcional: «1914–1918». El «circa» es del hecho entero.
/// - **La cita** apunta a una forma de texto y a un rango de ella, y guarda el
///   fragmento copiado: si el texto se vuelve a extraer, se reubica por el
///   fragmento (`TextAnchorRelocator`), como un subrayado. Si el fragmento ya
///   no está, el hecho se queda sin posición —conserva la fecha, el título y
///   el fragmento— en vez de irse: la fecha sigue siendo un dato. Un hecho
///   puesto a mano puede no tener cita.
/// - **Quién lo puso**: la persona o la IA, en una pasada (`ai_runs`) que se
///   puede deshacer. Editarlo lo vuelve de la persona, y quitar uno de la IA
///   lo anota en `ai_rejections` para que no vuelva.
///
/// Se va con su elemento. Con su forma de texto también, y entonces viaja en
/// la papelera del contenido (`content_trash.dated_events`) para volver con
/// ella. Viaja en la unión de bóvedas.
@DataClassName('DatedEventRow')
@TableIndex(name: 'idx_dated_events_item', columns: {#itemId})
@TableIndex(name: 'idx_dated_events_rendition', columns: {#renditionId})
@TableIndex(name: 'idx_dated_events_date', columns: {#dateFromYear})
@TableIndex(name: 'idx_dated_events_ai_run', columns: {#aiRunId})
class DatedEvents extends Table {
  @override
  String get tableName => 'dated_events';

  TextColumn get id => text()();

  TextColumn get itemId =>
      text().references(KnowledgeEntries, #id, onDelete: KeyAction.cascade)();

  /// El texto del que sale. `null` en un hecho puesto a mano sin cita.
  TextColumn get renditionId => text().nullable().references(
    Renditions,
    #id,
    onDelete: KeyAction.cascade,
  )();

  /// Qué pasó, corto: «Publica *El origen de las especies*».
  TextColumn get title => text()();

  // La fecha de inicio, como `property_values`: ver arriba.
  IntColumn get dateFromYear => integer()();
  IntColumn get dateFromMonth => integer()(); // 1-12
  IntColumn get dateFromDay => integer()(); // 1-31
  TextColumn get datePrecision => textEnum<DatePrecision>()();

  /// «Circa»: el hecho no se sabe con exactitud. Metadato de presentación;
  /// vale para el inicio y para el fin.
  BoolColumn get dateIsCirca => boolean().withDefault(const Constant(false))();

  // La fecha de fin, si el hecho es un tramo. Las cuatro vienen juntas o
  // ninguna; el mes y el día son los del primer día que cubre, como arriba.
  IntColumn get dateEndYear => integer().nullable()();
  IntColumn get dateEndMonth => integer().nullable()();
  IntColumn get dateEndDay => integer().nullable()();
  TextColumn get dateEndPrecision => textEnum<DatePrecision>().nullable()();

  /// Dónde está la cita en el texto de [renditionId]. Las dos vienen juntas o
  /// ninguna; solo tienen sentido con la forma.
  IntColumn get startOffset => integer().nullable()();
  IntColumn get endOffset => integer().nullable()();

  /// La cita, copiada: con ella se reubica si el texto cambia, y con ella se
  /// reconoce que la IA propone lo mismo dos veces.
  TextColumn get excerpt => text().nullable()();

  /// Quién lo puso.
  TextColumn get origin =>
      textEnum<ContentOrigin>().withDefault(const Constant('user'))();

  /// La pasada de la IA que lo puso: con ella se deshace entera. `null` en los
  /// de la persona y en los que la persona adoptó. Un hecho de la IA que llegó
  /// de otra bóveda sin su pasada también la tiene en `null`.
  TextColumn get aiRunId =>
      text().nullable().references(AiRuns, #id, onDelete: KeyAction.setNull)();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (length(trim(title)) > 0)',
    'CHECK (date_from_month BETWEEN 1 AND 12)',
    'CHECK (date_from_day BETWEEN 1 AND 31)',
    'CHECK ((date_end_year IS NULL) = (date_end_month IS NULL))',
    'CHECK ((date_end_year IS NULL) = (date_end_day IS NULL))',
    'CHECK ((date_end_year IS NULL) = (date_end_precision IS NULL))',
    'CHECK (date_end_month IS NULL OR date_end_month BETWEEN 1 AND 12)',
    'CHECK (date_end_day IS NULL OR date_end_day BETWEEN 1 AND 31)',
    'CHECK ((start_offset IS NULL) = (end_offset IS NULL))',
    'CHECK (start_offset IS NULL OR start_offset >= 0)',
    'CHECK (start_offset IS NULL OR end_offset > start_offset)',
    'CHECK (start_offset IS NULL OR rendition_id IS NOT NULL)',
    // La pasada es de lo que hizo la IA: lo de la persona no la lleva.
    "CHECK (origin <> 'user' OR ai_run_id IS NULL)",
  ];
}
