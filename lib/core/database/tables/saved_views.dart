import 'package:drift/drift.dart';
import 'package:sinapsis/core/domain/entities/library_view_mode.dart';

/// Una combinación de filtro, orden y modo de la Biblioteca, guardada con
/// nombre (F16).
///
/// `queryJson` guarda el filtro y el orden —lo que `LibraryQuery` ya
/// modela—, y `viewMode` el modo con que se muestra, que `LibraryQuery` no
/// tiene: son dos preguntas distintas («qué entra» y «cómo se ve») que
/// hasta acá vivían solo como estado de la pantalla. `position` es el orden
/// entre las vistas guardadas, no un campo de la consulta que guardan.
@DataClassName('SavedViewRow')
class SavedViews extends Table {
  @override
  String get tableName => 'saved_view';

  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get queryJson => text()();
  TextColumn get viewMode => textEnum<LibraryViewMode>()();
  IntColumn get position => integer()();

  /// Si aparece fijada en la navegación.
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
