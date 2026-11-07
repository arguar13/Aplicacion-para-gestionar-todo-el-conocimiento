import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/flashcards/data/repositories/flashcard_coverage_reader_impl.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/flashcard_coverage_reader.dart';

import '../../../../support/ai_organize_harness.dart';
import '../../../../support/item_rows.dart';
import '../../../../support/processed_rows.dart';

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

  group('cuántos de unos pueden tener tarjetas y no tienen ninguna (F46, '
      'paso 5h)', () {
    Future<int> count(List<String> ids) async =>
        (await reader.withoutCardsCountOf(ids)).getOrElse((f) => fail('$f'));

    test('los mismos que «withoutCards», solo de esos', () async {
      final ids = [
        'listo',
        'nota',
        'con-tarjetas',
        'procesando',
        'vacio',
        'borrado',
        'no-existe',
      ];

      expect(await count(ids), 2);
      expect(
        await count(ids),
        coverage(await reader.coverageOf(ids)).withoutCards.length,
      );
      expect(await count(['nota']), 1);
      expect(await count(['con-tarjetas']), 0);
    });

    test('uno repetido cuenta una vez; sin ninguno, cero', () async {
      expect(await count(['listo', 'listo', 'nota']), 2);
      expect(await count(const []), 0);
    });

    test('muchos, en una sola consulta', () async {
      expect(
        await count([
          'listo',
          for (var i = 0; i < 10000; i++) 'no-existe-$i',
          'nota',
        ]),
        2,
      );
    });

    test('una tarjeta nueva lo saca de la cuenta', () async {
      await vault.flashcards.create(
        itemId: 'nota',
        front: '¿Otra?',
        back: 'Sí',
      );

      expect(await count(['nota', 'listo']), 1);
    });
  });

  group('un documento procesado (F41, decisión I)', () {
    test('puede tener tarjetas por su texto procesado, aunque no tenga '
        'formas; uno sin nada que estudiar, no', () async {
      await insertProcessedRows(
        vault.db,
        id: 'procesado',
        title: 'Procesado',
        createdAt: DateTime(2026, 9, 4),
        parts: {
          ProcessedSection.summary: ['Lo principal.'],
        },
      );
      await insertProcessedRows(
        vault.db,
        id: 'claves',
        title: 'Solo palabras clave',
        createdAt: DateTime(2026, 9, 5),
        parts: {
          ProcessedSection.keywords: ['El Senado legislaba.'],
        },
      );
      await insertProcessedRows(
        vault.db,
        id: 'en-blanco',
        title: 'En blanco',
        parts: {
          ProcessedSection.notes: ['   '],
        },
      );

      final some = coverage(
        await reader.coverageOf(['procesado', 'claves', 'en-blanco', 'listo']),
      );

      expect(some.eligible, ['claves', 'procesado', 'listo']);
      expect(some.withoutCards, ['claves', 'procesado', 'listo']);
    });

    test('lo cuenta cuando llega su texto', () async {
      await insertProcessedRows(
        vault.db,
        id: 'procesado',
        title: 'Procesado',
        parts: const {},
      );
      final before = await reader.withoutCardsCountOf(['procesado']);
      expect(before.getOrElse((f) => fail('$f')), 0);

      await vault.db
          .into(vault.db.processedParts)
          .insert(
            ProcessedPartsCompanion.insert(
              id: 'parte',
              documentId: 'procesado',
              section: ProcessedSection.notes,
              position: 0,
              content: 'Una nota.',
              origin: ProcessedPartOrigin.user,
              createdAt: vault.now,
              updatedAt: vault.now,
            ),
          );

      final after = await reader.withoutCardsCountOf(['procesado']);
      expect(after.getOrElse((f) => fail('$f')), 1);
    });
  });
}
