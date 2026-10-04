import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/flashcards/data/repositories/flashcard_coverage_reader_impl.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/flashcard_coverage_reader.dart';

import '../../../../support/ai_organize_harness.dart';
import '../../../../support/item_rows.dart';

/// Qué elementos pueden tener tarjetas y cuáles ya tienen (F30): lo que
/// cuenta la hoja de «Crear tarjetas con IA» y el Repasar vacío.
void main() {
  late AiOrganizeHarness vault;
  late FlashcardCoverageReaderImpl reader;

  setUp(() async {
    vault = AiOrganizeHarness();
    reader = FlashcardCoverageReaderImpl(
      database: vault.db,
      telemetry: vault.telemetry,
    );
    // Del más viejo al más nuevo.
    await vault.source(
      'listo',
      title: 'Listo',
      content: 'Texto.',
      createdAt: DateTime(2026, 9),
    );
    await vault.note(
      'nota',
      title: 'Nota',
      content: 'Una idea.',
      createdAt: DateTime(2026, 9, 2),
    );
    await vault.source(
      'con-tarjetas',
      title: 'Con tarjetas',
      content: 'Texto.',
      createdAt: DateTime(2026, 9, 3),
    );
    await vault.flashcards.create(
      itemId: 'con-tarjetas',
      front: '¿Algo?',
      back: 'Sí',
    );
    // Lo que no entra: procesándose, sin texto y en la papelera.
    await vault.source(
      'procesando',
      title: 'Procesando',
      content: 'Texto.',
      processingState: ProcessingState.processing,
    );
    await vault.source('vacio', title: 'Vacío', content: '   ');
    await vault.source('borrado', title: 'Borrado', content: 'Texto.');
    await trashItemRows(vault.db, 'borrado');
  });

  tearDown(() => vault.close());

  FlashcardCoverage coverage(Either<Failure, FlashcardCoverage> result) =>
      result.getOrElse((f) => fail('$f'));

  test('de toda la biblioteca: lo vivo, listo y con texto, del más nuevo al '
      'más viejo, y cuáles ya tienen tarjetas', () async {
    final all = coverage(await reader.coverageOf(null));

    expect(all.eligible, ['con-tarjetas', 'nota', 'listo']);
    expect(all.withCards, {'con-tarjetas'});
    expect(all.withoutCards, ['nota', 'listo']);
  });

  test('de unos elementos: solo esos, también de a tandas', () async {
    final some = coverage(
      await reader.coverageOf([
        'listo',
        'procesando',
        'con-tarjetas',
        // Muchos que no existen: las tandas no pierden ni repiten nada.
        for (var i = 0; i < 1200; i++) 'no-existe-$i',
      ]),
    );

    expect(some.eligible, ['con-tarjetas', 'listo']);
    expect(some.withCards, {'con-tarjetas'});
  });

  test('cuántos podrían tener tarjetas y no tienen, al día', () async {
    final counts = reader.watchWithoutCardsCount();
    expect(await counts.first, 2);

    await vault.flashcards.create(itemId: 'nota', front: '¿Otra?', back: 'Sí');

    expect(await reader.watchWithoutCardsCount().first, 1);
  });
}
