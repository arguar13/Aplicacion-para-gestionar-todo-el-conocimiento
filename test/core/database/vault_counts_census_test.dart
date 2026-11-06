import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vault_counts.dart';

/// El censo de las tablas que cuentan las compuertas (F46, paso 2).
///
/// Cada paso de migración compara, antes y después, las filas de todo lo que
/// no toca (`VaultCounts`): una tabla que no está en ningún grupo no la cuida
/// ninguna migración futura, y puede perder filas en silencio. Cuando una tabla
/// nueva se suma al esquema, esta prueba falla hasta que tenga su grupo —o
/// diga, con el motivo, por qué no se cuenta—.
void main() {
  /// Todos los grupos de [VaultCounts], uno por renglón.
  const groups = <List<String>>[
    VaultCounts.userDataTables,
    VaultCounts.modelTables,
    VaultCounts.durabilityTables,
    VaultCounts.referenceTables,
    VaultCounts.viewsAndTemplatesTables,
    VaultCounts.notebookTables,
    VaultCounts.habitTables,
    VaultCounts.quizTables,
    VaultCounts.aiTables,
    VaultCounts.aiFieldChangeTables,
    VaultCounts.contentTrashTables,
    VaultCounts.studyTables,
    VaultCounts.itemSpaceTables,
    VaultCounts.datedEventTables,
    VaultCounts.processedTables,
    VaultCounts.processedImageTables,
    VaultCounts.studyCreationTables,
    VaultCounts.textNoteTables,
    VaultCounts.processedHeadingTables,
  ];

  /// Las tablas que ninguna compuerta cuenta, y por qué.
  const notCounted = <String, String>{
    'attachment_download':
        'estado de trabajo de este dispositivo: qué adjuntos se están '
        'bajando; se rehace solo',
    'processing_checkpoint':
        'estado de trabajo de este dispositivo: el avance de un trabajo largo, '
        'que se borra al terminar',
    'migration_issues': 'el registro de lo que pasó al migrar: no es contenido',
    'note_embedding':
        'derivada: los vectores de las notas se vuelven a calcular con el '
        'modelo',
    'property_value_embedding':
        'derivada: los vectores del vocabulario se vuelven a calcular con el '
        'modelo',
  };

  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('toda tabla del esquema está en un grupo de VaultCounts, o dice por '
      'qué no', () {
    final schema = {for (final table in db.allTables) table.actualTableName};
    final counted = {for (final group in groups) ...group};

    expect(
      schema.difference(counted).difference(notCounted.keys.toSet()),
      isEmpty,
      reason:
          'una tabla nueva necesita su grupo en VaultCounts —para que las '
          'migraciones que vienen la cuiden— o su motivo en notCounted',
    );
    expect(
      counted.difference(schema),
      isEmpty,
      reason: 'un grupo nombra una tabla que no existe',
    );
    expect(
      notCounted.keys.toSet().intersection(counted),
      isEmpty,
      reason: 'una tabla no puede estar contada y no contada',
    );
  });

  test('ninguna tabla está en dos grupos', () {
    final all = [for (final group in groups) ...group];

    expect(all.toSet(), hasLength(all.length));
  });
}
