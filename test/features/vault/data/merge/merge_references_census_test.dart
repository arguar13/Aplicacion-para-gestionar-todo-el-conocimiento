import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';

/// El censo de las referencias que cuida la unión de bóvedas (F46, paso 2).
///
/// Después de unir, `MergeGates` comprueba que ninguna tabla tenga más
/// referencias rotas que antes (`PRAGMA foreign_key_check`), tabla por tabla,
/// solo en las de su lista. Una tabla con claves foráneas que no está ahí puede
/// quedar con filas que apuntan a nada sin que nadie lo vea. Esta prueba
/// falla si una tabla con claves foráneas no está en la lista, o no dice por
/// qué no.
void main() {
  /// Las tablas con claves foráneas que la lista no tiene, y por qué.
  const notChecked = <String, String>{
    'attachment_download':
        'estado de trabajo de este dispositivo: la unión no la escribe',
    'processing_checkpoint':
        'estado de trabajo de este dispositivo: la unión no la escribe',
    'note_embedding':
        'derivada: la unión no la escribe, se vuelve a calcular con el modelo',
    'property_value_embedding':
        'derivada: la unión no la escribe, se vuelve a calcular con el modelo',
    'embeddings':
        'derivada de los chunks, que la fusión rehace: la unión no la escribe, '
        'y se va con su chunk en cascada',
    'notebook_item':
        'los cuadernos no viajan en la unión: cada dispositivo arma los suyos',
    'suggestions':
        'las sugerencias son de cada dispositivo: la unión no las escribe, y '
        'se van con su elemento en cascada',
  };

  test('toda tabla con claves foráneas está en la lista de MergeGates, o dice '
      'por qué no', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final source = File(
      'lib/features/vault/data/merge/merge_gates.dart',
    ).readAsStringSync();
    final start = source.indexOf('static const _referencing');
    expect(start, isNonNegative);
    final listed = {
      for (final m in RegExp(
        r"'(\w+)',",
      ).allMatches(source.substring(start, source.indexOf('];', start))))
        m.group(1)!,
    };

    final withKeys = <String>{};
    for (final table in db.allTables) {
      final keys = await db
          .customSelect(
            'SELECT COUNT(*) AS n FROM pragma_foreign_key_list(?)',
            variables: [Variable.withString(table.actualTableName)],
          )
          .getSingle();
      if (keys.read<int>('n') > 0) withKeys.add(table.actualTableName);
    }

    expect(
      withKeys.difference(listed).difference(notChecked.keys.toSet()),
      isEmpty,
      reason:
          'una tabla con claves foráneas necesita estar en '
          'MergeGates._referencing, o su motivo en notChecked',
    );
    expect(
      notChecked.keys.toSet().intersection(listed),
      isEmpty,
      reason: 'una tabla no puede estar en la lista y afuera a la vez',
    );
    expect(
      notChecked.keys.toSet().difference(withKeys),
      isEmpty,
      reason: 'una tabla de notChecked ya no tiene claves foráneas: sacarla',
    );
    expect(listed, contains('processed_headings'));
  });
}
