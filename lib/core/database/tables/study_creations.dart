import 'package:drift/drift.dart';

/// Una creación de «Lo creado» (F43, v48): lo que se generó en Repasar sobre
/// lo procesado —una presentación, un mapa mental, un informe, un mazo, un
/// cuestionario, una infografía, una tabla— o una de las tres vistas vivas de
/// extraer (el texto completo, el resumen, la síntesis).
///
/// - **El tipo, el recorte y las opciones** son de la persona: qué eligió en la
///   hoja de personalizar. El tipo y el recorte se guardan como texto estable
///   (`StudyCreationKind.storageKey`, `CreationScope.storageKey`): un tipo que
///   esta versión no conoce —una copia de una app más nueva— se conserva y no
///   se muestra, en vez de romper la lista.
/// - **El contenido** es un JSON con el esquema de su tipo (decisión G): la IA
///   devuelve datos y la app dibuja. Los tres de extraer no guardan contenido
///   (decisión E): son vistas vivas sobre el resumen, la síntesis y las
///   palabras clave del procesado, así que [contentJson] es `null`.
/// - **Las fuentes** son los ids de los documentos procesados que de verdad se
///   usaron, como una lista JSON y SIN clave foránea, a propósito: si un
///   procesado se borra, la creación sigue ahí y la ficha dice «fuente
///   borrada». Nada se va en cascada.
/// - **El estado** dice si espera en la cola, se está generando, está lista o
///   falló —con su motivo—. Lo que quedó en cola o generándose sobrevive a que
///   se cierre la app y se retoma al abrirla (`CreationQueue.resume`).
/// - **Borrar es mandar a la papelera** ([deletedAt]); solo vaciarla la borra
///   de verdad. Viaja en la copia de la bóveda y en la unión.
@DataClassName('StudyCreationRow')
//
// «Lo creado» se lista con lo más nuevo arriba —por cuándo se creó, que no
// cambia al renombrar—, de todo o de un recorte: los dos índices de abajo. El
// de [status] es el de la cola, que al abrir la app busca lo que quedó
// esperando.
@TableIndex(
  name: 'idx_study_creations_scope',
  columns: {#scopeKind, #scopeId, #createdAt},
)
@TableIndex(name: 'idx_study_creations_created', columns: {#createdAt})
@TableIndex(name: 'idx_study_creations_status', columns: {#status})
class StudyCreations extends Table {
  @override
  String get tableName => 'study_creations';

  TextColumn get id => text()();

  /// Qué es: `StudyCreationKind.storageKey`.
  TextColumn get kind => text()();

  /// El título, que pone la IA al terminar o la persona al renombrar. `null`
  /// mientras no lo hay: la fila muestra el nombre de su tipo.
  TextColumn get title => text().nullable()();

  /// Sobre qué recorte de Procesado se creó: `CreationScope.storageKey`
  /// partido en su clase ([scopeKind]) y su id ([scopeId], `null` en «Todo lo
  /// procesado»), para listar por recorte con un índice.
  TextColumn get scopeKind => text()();
  TextColumn get scopeId => text().nullable()();

  /// Los documentos procesados que se usaron, una lista JSON de ids.
  TextColumn get sourceIdsJson => text().withDefault(const Constant('[]'))();

  /// Lo elegido en la hoja de personalizar, un objeto JSON: cada tipo sabe leer
  /// el suyo.
  TextColumn get optionsJson => text().withDefault(const Constant('{}'))();

  /// El contenido, en el JSON del esquema de su tipo; `null` mientras no está
  /// listo y siempre en los tres de extraer.
  TextColumn get contentJson => text().nullable()();

  /// La versión del esquema de [contentJson]: un visor que cambia su esquema
  /// lee lo viejo sabiendo de cuál es.
  IntColumn get contentVersion => integer().withDefault(const Constant(1))();

  /// En qué idioma se pidió, como `es` o `en`.
  TextColumn get languageCode => text()();

  /// `queued`, `generating`, `ready` o `failed`: `CreationStatus.storageKey`.
  TextColumn get status => text()();

  /// Por qué falló (`CreationFailure.storageKey`), y el detalle técnico para el
  /// registro —nunca se le muestra tal cual a la persona—. Solo con `failed`.
  TextColumn get failure => text().nullable()();
  TextColumn get failureDetail => text().nullable()();

  /// Cuánto va, de 0 a 1, y en qué paso (`CreationStep.storageKey`), mientras
  /// se genera.
  RealColumn get progress => real().nullable()();
  TextColumn get progressStep => text().nullable()();

  /// Si se pidió con «Generar ahora» —con el turno y la cuota de la persona—
  /// y no con «Generar más tarde» —con la cola de fondo y su tope—. Es lo que
  /// decide con qué turno se retoma después de cerrar la app.
  BoolColumn get runNow => boolean().withDefault(const Constant(false))();

  /// Cuántas veces se empezó a generar sin terminar porque la app se cerró:
  /// después de tres, se da por fallida en vez de reintentarla en cada
  /// arranque (como la cola de procesamiento de F21).
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// Con qué modelo se escribió, para la ficha y para «Volver a generar».
  TextColumn get modelName => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Cuándo se mandó a la papelera; `null` si está viva.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (status IN ('queued', 'generating', 'ready', 'failed'))",
    "CHECK ((status = 'failed') = (failure IS NOT NULL))",
    'CHECK (progress IS NULL OR (progress >= 0 AND progress <= 1))',
    'CHECK (attempts >= 0)',
    'CHECK (content_version >= 1)',
    "CHECK (scope_kind <> 'all' OR scope_id IS NULL)",
    "CHECK (scope_kind = 'all' OR scope_id IS NOT NULL)",
    'CHECK (title IS NULL OR length(trim(title)) > 0)',
  ];
}
