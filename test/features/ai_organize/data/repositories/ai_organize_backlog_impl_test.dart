import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/features/ai_organize/data/repositories/ai_organize_backlog_impl.dart';
import 'package:sinapsis/features/ai_organize/data/services/prefs_ai_organize_memory.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_organize_backlog.dart';

import '../../../../support/ai_organize_harness.dart';
import '../../../../support/item_rows.dart';

void main() {
  late AiOrganizeHarness vault;
  late AiOrganizeBacklogImpl backlog;
  final epoch = DateTime(2026, 10);

  setUp(() {
    vault = AiOrganizeHarness();
    backlog = AiOrganizeBacklogImpl(vault.db);
  });

  tearDown(() => vault.close());

  /// Hasta cuándo una nota tiene que estar quieta: un poco después de ahora,
  /// así las notas recién guardadas cuentan.
  DateTime quiet() => vault.now.add(const Duration(minutes: 1));

  test('solo lo vivo y listo, que la IA no organizó todavía', () async {
    await vault.source('listo', title: 'Listo', content: 'Texto.');
    await vault.source(
      'procesando',
      title: 'Procesando',
      content: 'Texto.',
      processingState: ProcessingState.processing,
    );
    await vault.source(
      'fallido',
      title: 'Fallido',
      content: 'Texto.',
      processingState: ProcessingState.failed,
    );
    await vault.source('borrado', title: 'Borrado', content: 'Texto.');
    await trashItemRows(vault.db, 'borrado');
    await vault.source('hecho', title: 'Hecho', content: 'Texto.');
    await vault.runs.finishRun(await vault.startRun('hecho'));
    await vault.source('deshecho', title: 'Deshecho', content: 'Texto.');
    await vault.runs.undoRun(await vault.startRun('deshecho'));

    expect(
      await backlog.nextFresh(since: epoch, notesQuietBefore: quiet()),
      'listo',
    );
    expect(
      await backlog.nextFresh(
        since: epoch,
        notesQuietBefore: quiet(),
        skip: {'listo'},
      ),
      isNull,
    );
    expect(
      await backlog.count(epoch: epoch, notesQuietBefore: quiet()),
      const AiBacklogCount(fresh: 1),
    );
  });

  test('separa lo nuevo de la biblioteca que ya existía', () async {
    await vault.source('nuevo', title: 'Nuevo', content: 'Texto.');
    await vault.source(
      'viejo',
      title: 'Viejo',
      content: 'Texto.',
      createdAt: DateTime(2026, 9),
    );
    await vault.source(
      'mas-viejo',
      title: 'Más viejo',
      content: 'Texto.',
      createdAt: DateTime(2026, 8),
    );

    expect(
      await backlog.count(epoch: epoch, notesQuietBefore: quiet()),
      const AiBacklogCount(fresh: 1, existing: 2),
    );
    // De la biblioteca que ya existía, lo más reciente primero.
    expect(
      await backlog.nextExisting(before: epoch, notesQuietBefore: quiet()),
      'viejo',
    );
  });

  test('una nota, solo cuando lleva un rato sin cambios', () async {
    await vault.note('n', title: 'Nota', content: 'Una idea.');

    expect(
      await backlog.nextFresh(since: epoch, notesQuietBefore: vault.now),
      'n',
    );
    expect(
      await backlog.nextFresh(
        since: epoch,
        notesQuietBefore: vault.now.subtract(const Duration(seconds: 1)),
      ),
      isNull,
    );
  });

  test('las notas que cambiaron después de su pasada, con la huella que '
      'vio', () async {
    await vault.note('n', title: 'Nota', content: 'Una idea.');
    await vault.runs.finishRun(
      (await vault.runs.startRun(
        'n',
        contentSimhash: '00ff',
      )).getOrElse((f) => fail('$f')),
    );
    expect(await backlog.editedNotes(quietBefore: quiet()), isEmpty);

    vault.now = vault.now.add(const Duration(minutes: 5));
    await vault.note('n', title: 'Nota', content: 'Otra idea.');

    // Recién guardada: todavía se está escribiendo.
    expect(
      await backlog.editedNotes(
        quietBefore: vault.now.subtract(const Duration(seconds: 1)),
      ),
      isEmpty,
    );
    expect(
      (await backlog.editedNotes(
        quietBefore: vault.now,
      )).map((n) => (n.itemId, n.simhashSeen)),
      [('n', '00ff')],
    );
  });

  group('una pasada de solo tarjetas (F30) no cuenta como organizar', () {
    Future<String> flashcardsOnlyRun(String itemId) async =>
        (await vault.runs.startRun(
          itemId,
          flashcardsOnly: true,
        )).getOrElse((f) => fail('$f'));

    test('el elemento sigue pendiente, terminada o deshecha, y sin gastar '
        'intentos', () async {
      await vault.source(
        'viejo',
        title: 'Viejo',
        content: 'Texto.',
        createdAt: DateTime(2026, 9),
      );
      await vault.runs.finishRun(await flashcardsOnlyRun('viejo'));
      await vault.runs.undoRun(await flashcardsOnlyRun('viejo'));
      // Tres más, a medias: con las de organizar, el tope de intentos.
      for (var i = 0; i < kMaxAiRunAttempts; i++) {
        await flashcardsOnlyRun('viejo');
      }

      expect(
        await backlog.nextExisting(before: epoch, notesQuietBefore: quiet()),
        'viejo',
      );
      expect(
        await backlog.count(epoch: epoch, notesQuietBefore: quiet()),
        const AiBacklogCount(existing: 1),
      );

      // Una de organizar, terminada, sí lo saca.
      await vault.runs.finishRun(await vault.startRun('viejo'));
      expect(
        await backlog.nextExisting(before: epoch, notesQuietBefore: quiet()),
        isNull,
      );
    });

    test('una nota que cambió se mira contra su última pasada de organizar, '
        'no contra la de tarjetas', () async {
      await vault.note('n', title: 'Nota', content: 'Una idea.');
      await vault.runs.finishRun(
        (await vault.runs.startRun(
          'n',
          contentSimhash: '00ff',
        )).getOrElse((f) => fail('$f')),
      );
      vault.now = vault.now.add(const Duration(minutes: 5));
      await vault.note('n', title: 'Nota', content: 'Otra idea.');
      vault.now = vault.now.add(const Duration(minutes: 5));
      // Las tarjetas, después del cambio: sin huella, como las pide Repasar.
      await vault.runs.finishRun(await flashcardsOnlyRun('n'));

      expect(
        (await backlog.editedNotes(
          quietBefore: vault.now,
        )).map((n) => (n.itemId, n.simhashSeen)),
        [('n', '00ff')],
      );
    });

    test('deshacerla no hace que la IA deje de tocar el elemento', () async {
      await vault.source('a', title: 'A', content: 'Texto.');
      await vault.runs.finishRun(await vault.startRun('a'));
      await vault.runs.undoRun(await flashcardsOnlyRun('a'));

      expect(
        (await vault.runs.undoneItemsAmong(['a'])).getOrElse((f) => fail('$f')),
        isEmpty,
      );

      // La de organizar, deshecha, sí: aunque después haya una de tarjetas.
      await vault.source('b', title: 'B', content: 'Texto.');
      await vault.runs.undoRun(await vault.startRun('b'));
      vault.now = vault.now.add(const Duration(minutes: 1));
      await vault.runs.finishRun(await flashcardsOnlyRun('b'));
      expect(
        (await vault.runs.undoneItemsAmong(['b'])).getOrElse((f) => fail('$f')),
        {'b'},
      );
    });
  });

  test('la memoria del dispositivo fija el comienzo una sola vez', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final memory = PrefsAiOrganizeMemory(prefs: prefs, clock: vault.clock);

    final first = await memory.epoch();
    vault.now = vault.now.add(const Duration(days: 3));

    expect(await memory.epoch(), first);
  });
}
