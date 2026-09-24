import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/note_template.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/blocks/data/repositories/note_template_repository_impl.dart';

import '../../../../support/fake_id_generator.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Contra SQLite real, en memoria: lo que hay que verificar es que los
/// bloques y las propiedades sobreviven a una vuelta completa por la base
/// —codificados como JSON—.
void main() {
  late AppDatabase db;
  late NoteTemplateRepositoryImpl repository;
  late FakeIdGenerator ids;
  var now = DateTime(2026, 9, 24, 10);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    ids = FakeIdGenerator();
    now = DateTime(2026, 9, 24, 10);
    repository = NoteTemplateRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      ids: ids,
      clock: () => now,
    );
  });

  tearDown(() => db.close());

  group('create', () {
    test(
      'guarda los bloques y las propiedades, y los devuelve iguales',
      () async {
        final blocks = [
          const ContentBlock.heading(text: 'Reunión'),
          const ContentBlock.checklistItem(text: 'Temario'),
        ];
        const properties = [
          TemplateProperty(
            definitionId: 'def-tipo',
            definitionName: 'Tipo',
            value: 'Reunión',
          ),
        ];

        final template = await repository.create(
          name: 'Reunión de equipo',
          blocks: blocks,
          properties: properties,
        );

        expect(template.name, 'Reunión de equipo');
        expect(template.createdAt, now);

        final all = await repository.watchAll().first;
        expect(all, hasLength(1));
        expect(all.single.blocks, blocks);
        expect(all.single.properties, properties);
      },
    );

    test('una plantilla sin propiedades guarda una lista vacía', () async {
      await repository.create(
        name: 'Nota simple',
        blocks: const [ContentBlock.paragraph(text: '')],
        properties: const [],
      );

      final saved = (await repository.watchAll().first).single;
      expect(saved.properties, isEmpty);
    });
  });

  group('rename y delete', () {
    test('cada una cambia solo lo suyo', () async {
      final a = await repository.create(
        name: 'A',
        blocks: const [],
        properties: const [],
      );
      final b = await repository.create(
        name: 'B',
        blocks: const [],
        properties: const [],
      );

      await repository.rename(a.id, 'A renombrada');
      final afterRename = await repository.watchAll().first;
      expect(afterRename.firstWhere((t) => t.id == a.id).name, 'A renombrada');
      expect(afterRename.firstWhere((t) => t.id == b.id).name, 'B');

      await repository.delete(a.id);
      final afterDelete = await repository.watchAll().first;
      expect(afterDelete.map((t) => t.id), [b.id]);
    });
  });
}
