import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/bulk_writer_holder.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';

/// El puente entre repositorios para el modo lote (F19, 19.4): puro, sin
/// tocar la base —eso ya lo prueba `library_repository_impl_test.dart` de
/// punta a punta, con `LibraryRepositoryImpl` y `ReferenceRepositoryImpl`
/// compartiendo uno—.
void main() {
  test('sin ningún lote abierto, no hay escritor activo', () {
    final holder = BulkWriterHolder();
    expect(holder.current, isNull);
  });

  test(
    'mientras corre runWith, current es el escritor que se le pasó',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final holder = BulkWriterHolder();
      final writer = KnowledgeEntryWriter(db);

      KnowledgeEntryWriter? seenInside;
      await holder.runWith(writer, () async {
        seenInside = holder.current;
      });

      expect(seenInside, same(writer));
      expect(holder.current, isNull, reason: 'vuelve a nada al terminar');
    },
  );

  test('un fallo adentro igual restaura current a lo que había', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final holder = BulkWriterHolder();
    final writer = KnowledgeEntryWriter(db);

    await expectLater(
      holder.runWith(writer, () async {
        throw StateError('falla adentro del lote');
      }),
      throwsA(isA<StateError>()),
    );

    expect(holder.current, isNull);
  });
}
