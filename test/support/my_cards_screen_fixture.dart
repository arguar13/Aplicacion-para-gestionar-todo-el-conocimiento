import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/card_phase.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/my_cards_screen.dart';

import 'item_rows.dart';
import 'library_harness.dart';

/// Lo común de las pruebas de «Mis tarjetas» (F31, ola 2): la base de la
/// harness con dos elementos, una forma de sembrar tarjetas en la etapa que se
/// pida, y de montar la pantalla.
class MyCardsFixture {
  MyCardsFixture(this.harness);

  final LibraryHarness harness;

  AppDatabase get db => harness.database;

  /// El reloj de la harness: las 10:00 del 11 de septiembre de 2026.
  static final now = DateTime(2026, 9, 11, 10);

  /// Con [extraOverrides] cambia proveedores en el contenedor de la harness
  /// (un doble que falla, por ejemplo): tienen que ir ahí y no en un
  /// `ProviderScope` aparte, que no los hace llegar a lo que ya se leyó.
  static Future<MyCardsFixture> create({
    List<Override> extraOverrides = const [],
  }) async {
    final harness = await LibraryHarness.create(extraOverrides: extraOverrides);
    final fixture = MyCardsFixture(harness);
    await insertItemRows(fixture.db, id: 'roma', title: 'Imperio romano');
    await insertItemRows(fixture.db, id: 'grecia', title: 'Grecia clásica');
    return fixture;
  }

  Future<void> card(
    String id, {
    String itemId = 'roma',
    String? front,
    String back = 'respuesta',
    CardPhase phase = CardPhase.review,
    int interval = 15,
    DateTime? dueAt,
    bool suspended = false,
    DateTime? buriedUntil,
    FlashcardKind kind = FlashcardKind.freeRecall,
    String? groupId,
    int? clozeIndex,
    double ease = 2.5,
    DateTime? createdAt,
  }) {
    final (reps, days, step, reviewed) = switch (phase) {
      CardPhase.newCard => (0, 0, null, null),
      CardPhase.learning => (0, 0, 0, now),
      CardPhase.relearning => (0, 1, 0, now),
      CardPhase.review => (3, interval, null, DateTime(2026, 8, 20)),
    };
    return db
        .into(db.flashcards)
        .insert(
          FlashcardsCompanion.insert(
            id: id,
            itemId: itemId,
            front: front ?? 'Pregunta $id',
            back: back,
            dueAt: dueAt ?? now,
            createdAt: createdAt ?? DateTime(2026, 8),
            easeFactor: Value(ease),
            repetitions: Value(reps),
            intervalDays: Value(days),
            learningStep: Value(step),
            lastReviewedAt: Value(reviewed),
            suspended: Value(suspended),
            buriedUntil: Value(buriedUntil),
            kind: Value(kind),
            groupId: Value(groupId),
            clozeIndex: Value(clozeIndex),
          ),
        );
  }

  Future<FlashcardRow> row(String id) =>
      (db.select(db.flashcards)..where((f) => f.id.equals(id))).getSingle();

  Future<FlashcardRow?> maybeRow(String id) => (db.select(
    db.flashcards,
  )..where((f) => f.id.equals(id))).getSingleOrNull();

  Future<void> pump(
    WidgetTester tester, {
    StudyScope scope = const StudyScope.all(),
  }) async {
    await tester.pumpWidget(harness.wrap(MyCardsScreen(initialScope: scope)));
    await tester.pumpAndSettle();
  }
}
