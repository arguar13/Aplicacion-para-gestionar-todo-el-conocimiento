import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/flashcards.dart';
import 'package:sinapsis/core/domain/entities/card_phase.dart';

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

  /// La etapa de la tarjeta ANTES de contestarla (F31, v39). Con ella se
  /// cuentan las nuevas y los repasos del día contra sus límites: una nueva
  /// cuenta una vez, al contestarla por primera vez; un repaso cuenta cuando
  /// la tarjeta ya estaba en repaso, y los pasos cortos de aprender o
  /// reaprender no cuentan. En lo de antes de v39, `review` —lo que todo era—,
  /// salvo la primera respuesta de cada tarjeta (`interval_before = 0`), que la
  /// migración marca `newCard`.
  TextColumn get phaseBefore =>
      textEnum<CardPhase>().withDefault(const Constant('review'))();

  /// El paso de aprendizaje antes y después (F31, v39): nulo si no estaba en
  /// ninguno. Es lo que permite pintar «repasó 20 veces en el paso de 10
  /// minutos» en las estadísticas, y que deshacer sepa de dónde partió.
  IntColumn get stepBefore => integer().nullable()();
  IntColumn get stepAfter => integer().nullable()();

  /// Lo que hace falta para DESHACER este repaso y dejar la tarjeta exactamente
  /// como estaba (F31, v39): cuándo tocaba, cuándo se repasó antes y cuántas
  /// repeticiones llevaba (el intervalo y la facilidad ya estaban en
  /// [intervalBefore] y [easeBefore]; el paso, en [stepBefore]).
  ///
  /// `due_before` nulo = un repaso de antes de v39, del que no se guardó eso:
  /// no se puede deshacer.
  DateTimeColumn get dueBefore => dateTime().nullable()();
  DateTimeColumn get lastReviewedBefore => dateTime().nullable()();
  IntColumn get repetitionsBefore => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
