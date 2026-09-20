import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/flashcards.dart';

/// El historial de repasos de las tarjetas (F11): uno por cada vez que se
/// contestó una.
///
/// Hasta ahora cada repaso sobrescribía el estado de la tarjeta y el dato se
/// perdía: sin este registro no hay forma de mirar cómo le fue a quien estudia
/// a lo largo del tiempo. Es solo un registro —lo que decide cuándo volver a
/// ver una tarjeta sigue siendo el estado de la propia tarjeta (SM-2)—.
///
/// [grade] es el nombre de la nota de repaso (`again`, `hard`, `good`, `easy`)
/// y [quality] la calidad de SM-2 que le corresponde (0, 3, 4 y 5). Se guardan
/// los dos: el nombre es lo que eligió la persona; el número, lo que usó el
/// algoritmo.
@DataClassName('ReviewLogRow')
@TableIndex(
  name: 'idx_review_log_flashcard',
  columns: {#flashcardId, #reviewedAt},
)
class ReviewLogs extends Table {
  @override
  String get tableName => 'review_log';

  TextColumn get id => text()();

  TextColumn get flashcardId =>
      text().references(Flashcards, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get reviewedAt => dateTime()();

  TextColumn get grade => text()();

  IntColumn get quality => integer()();

  /// El intervalo, en días, antes y después del repaso.
  IntColumn get intervalBefore => integer()();

  IntColumn get intervalAfter => integer()();

  /// El factor de facilidad de SM-2 antes y después.
  RealColumn get easeBefore => real()();

  RealColumn get easeAfter => real()();

  /// El dispositivo donde se repasó.
  TextColumn get deviceId => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
