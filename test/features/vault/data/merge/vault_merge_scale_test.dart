import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/chunk_invariant_verifier.dart';

import '../../../../support/test_vault.dart';

/// La fusión a escala moderada (F11): 1.500 elementos —1.200 fuentes con texto
/// y 300 notas— entran a una bóveda vacía, y una variante con cambios se
/// fusiona encima.
///
/// No es el benchmark: mide que el tiempo crece con lo que CAMBIA y no con lo
/// que HAY, que las cuentas dan, y que el texto llega exacto. La de 10.000
/// elementos, con la bóveda sintética, está en el cierre de F11.
void main() {
  late TestVault tel;
  late TestVault pc;

  setUp(() async {
    tel = await TestVault.create(deviceId: 'tel');
    pc = await TestVault.create(deviceId: 'pc');
  });

  tearDown(() async {
    await tel.dispose();
    await pc.dispose();
  });

  Future<(int, int)> textOf(TestVault vault) async {
    final row = await vault.db
        .customSelect(
          'SELECT COUNT(*) AS n, SUM(LENGTH(content)) AS bytes FROM renditions',
        )
        .getSingle();
    return (row.read<int>('n'), row.read<int>('bytes'));
  }

  test(
    'una bóveda entera, después una variante, después la misma otra vez',
    () async {
      pc.at(1);
      await pc.bulk(sources: 1200, notes: 300);
      final stopwatch = Stopwatch()..start();

      // La primera: todo es nuevo.
      tel.at(2);
      final first = await tel.mergeFrom(pc);
      final firstMs = stopwatch.elapsedMilliseconds;

      expect(first.itemsAdded, 1500);
      expect(first.renditionsAdded, 1500);
      expect(first.sourcesChunked, 1200);
      expect(first.conflictsRecorded, 0);
      expect(await tel.count('item'), 1500);
      expect(await tel.count('source'), 1200);
      expect(await tel.count('note'), 300);
      // El texto, exacto: la misma cantidad de formas y de caracteres.
      expect(await textOf(tel), await textOf(pc));
      final report = await verifyChunkInvariant(tel.db);
      expect(
        report.holds,
        isTrue,
        reason: report.violations.take(3).join('; '),
      );
      expect(report.sourcesChecked, 1200);

      // La misma copia otra vez: no hay nada que hacer, y cuesta casi nada.
      stopwatch
        ..reset()
        ..start();
      tel.at(3);
      final again = await tel.mergeFrom(pc);
      final againMs = stopwatch.elapsedMilliseconds;
      expect(again.changedNothing, isTrue);

      // Una variante: 100 títulos editados más recientemente y 50 fuentes
      // nuevas.
      pc.at(30);
      await pc.db.customStatement(
        "UPDATE item SET title = title || ' (editada)', "
        'updated_at = updated_at + 1000 '
        "WHERE id IN (SELECT id FROM item WHERE id LIKE 's%' "
        'ORDER BY id LIMIT 100)',
      );
      await pc.bulk(sources: 50, from: 1200);
      stopwatch
        ..reset()
        ..start();
      tel.at(31);
      final variant = await tel.mergeFrom(pc);
      final variantMs = stopwatch.elapsedMilliseconds;

      expect(variant.itemsAdded, 50);
      expect(variant.itemsUpdated, 100);
      expect(variant.fieldsUpdated, 100);
      expect(variant.sourcesChunked, 50);
      expect(variant.conflictsRecorded, 0);
      expect(await tel.count('item'), 1550);
      expect(await textOf(tel), await textOf(pc));

      // Lo que costó, para quien lea el registro.
      // ignore: avoid_print
      print(
        'fusión a escala: 1.500 elementos nuevos en $firstMs ms; la misma '
        'copia otra vez en $againMs ms; una variante (100 cambios, 50 '
        'nuevos) en $variantMs ms',
      );
      // El tiempo sigue a lo que cambia y no a lo que hay: rehacer lo que ya
      // estaba costaría lo mismo que traerlo.
      expect(againMs, lessThan(firstMs));
      expect(variantMs, lessThan(firstMs));
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
