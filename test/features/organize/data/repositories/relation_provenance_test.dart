import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' show right;
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/entities/ai_provenance.dart';
import 'package:sinapsis/core/domain/entities/ai_rejection_kind.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/relation_update_outcome.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/ai_organize/data/repositories/ai_run_repository_impl.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/organize/data/repositories/organize_repository_impl.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';
import '../../../../support/item_rows.dart';

class _MockTelemetryService extends Mock implements TelemetryService {}

/// Vínculos y propiedades que hizo la IA (F27): editarlos los adopta,
/// «no era» los borra y los recuerda, y lo recordado no vuelve. Contra SQLite
/// real: la clave única de un vínculo es parte de lo que se prueba.
void main() {
  late AppDatabase db;
  late OrganizeRepositoryImpl repository;
  late AiRunRepositoryImpl runs;
  final now = DateTime(2026, 10, 2, 10);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final ids = FakeIdGenerator();
    repository = OrganizeRepositoryImpl(
      database: db,
      telemetry: _MockTelemetryService(),
      ids: ids,
      clock: () => now,
    );
    runs = AiRunRepositoryImpl(
      database: db,
      telemetry: _MockTelemetryService(),
      ids: ids,
      clock: () => now,
    );
    for (final id in ['a', 'b']) {
      await insertItemRows(db, id: id, title: 'Elemento $id');
    }
  });

  tearDown(() => db.close());

  Future<String> startRun() async =>
      (await runs.startRun('a')).getOrElse((f) => fail('$f'));

  Future<RelationRow> onlyRelation() => db.select(db.relations).getSingle();

  Future<RelationRow> aiRelation({
    RelationKind kind = RelationKind.relatedTo,
    String from = 'a',
    String to = 'b',
  }) async {
    final run = await startRun();
    final created = await repository.createRelation(
      fromItemId: from,
      toItemId: to,
      kind: kind,
      note: 'Hablan de lo mismo',
      ai: AiProvenance(runId: run, confidence: 0.8),
    );
    expect(created.isRight(), isTrue, reason: '$created');
    return (db.select(
      db.relations,
    )..where((r) => r.kind.equalsValue(kind))).getSingle();
  }

  group('crear', () {
    test('sin procedencia es de la persona, como siempre', () async {
      await repository.createRelation(
        fromItemId: 'a',
        toItemId: 'b',
        kind: RelationKind.cites,
      );

      final row = await onlyRelation();
      expect(row.origin, ContentOrigin.user);
      expect(row.aiRunId, isNull);
      expect(row.confidence, isNull);
    });

    test('con procedencia queda de la IA, con su pasada, su confianza y su '
        'motivo', () async {
      final row = await aiRelation();

      expect(row.origin, ContentOrigin.ai);
      expect(row.aiRunId, isNotNull);
      expect(row.confidence, 0.8);
      expect(row.note, 'Hablan de lo mismo');

      final seen = await repository.watchRelationsForItem('a').first;
      expect(seen.single.isFromAi, isTrue);
      expect(seen.single.confidence, 0.8);
    });
  });

  group('editar', () {
    test('cambia el tipo y la frase, y lo adopta', () async {
      final row = await aiRelation();

      final result = await repository.updateRelation(
        row.id,
        kind: RelationKind.contradicts,
        note: '  Dicen lo contrario  ',
      );

      expect(
        result,
        right<Failure, RelationUpdateOutcome>(RelationUpdateOutcome.updated),
      );
      final edited = await onlyRelation();
      expect(edited.kind, RelationKind.contradicts);
      expect(edited.note, 'Dicen lo contrario');
      expect(edited.origin, ContentOrigin.user);
      expect(edited.aiRunId, isNull);
      expect(edited.confidence, isNull);
    });

    test('una frase vacía la quita', () async {
      final row = await aiRelation();

      await repository.updateRelation(row.id, kind: row.kind, note: '   ');

      expect((await onlyRelation()).note, isNull);
    });

    test('si ya hay uno de ese tipo entre los dos, se funden en ese', () async {
      final row = await aiRelation();
      await repository.createRelation(
        fromItemId: 'a',
        toItemId: 'b',
        kind: RelationKind.contradicts,
        note: 'La de la persona',
      );

      final result = await repository.updateRelation(
        row.id,
        kind: RelationKind.contradicts,
      );

      expect(
        result,
        right<Failure, RelationUpdateOutcome>(RelationUpdateOutcome.merged),
      );
      final kept = await onlyRelation();
      expect(kept.kind, RelationKind.contradicts);
      // Sin frase nueva, queda la que ya tenía.
      expect(kept.note, 'La de la persona');
      expect(kept.origin, ContentOrigin.user);
    });

    test('al fundirse, la frase nueva gana', () async {
      final row = await aiRelation();
      await repository.createRelation(
        fromItemId: 'a',
        toItemId: 'b',
        kind: RelationKind.contradicts,
        note: 'Vieja',
      );

      await repository.updateRelation(
        row.id,
        kind: RelationKind.contradicts,
        note: 'Nueva',
      );

      expect((await onlyRelation()).note, 'Nueva');
    });

    test('el mismo tipo en el otro sentido no es el mismo vínculo', () async {
      final row = await aiRelation();
      await repository.createRelation(
        fromItemId: 'b',
        toItemId: 'a',
        kind: RelationKind.continues,
      );

      final result = await repository.updateRelation(
        row.id,
        kind: RelationKind.continues,
      );

      expect(
        result,
        right<Failure, RelationUpdateOutcome>(RelationUpdateOutcome.updated),
      );
      expect(await db.select(db.relations).get(), hasLength(2));
    });

    test('una extracción no cambia de tipo, ni se convierte en una', () async {
      await repository.createRelation(
        fromItemId: 'a',
        toItemId: 'b',
        kind: RelationKind.extractedFrom,
      );
      final extraction = await onlyRelation();

      final away = await repository.updateRelation(
        extraction.id,
        kind: RelationKind.relatedTo,
      );
      expect(away.getLeft().toNullable(), isA<ValidationFailure>());

      await db.delete(db.relations).go();
      final row = await aiRelation();
      final into = await repository.updateRelation(
        row.id,
        kind: RelationKind.extractedFrom,
      );
      expect(into.getLeft().toNullable(), isA<ValidationFailure>());
      expect((await onlyRelation()).kind, RelationKind.relatedTo);
    });

    test('uno que ya no existe es un fallo, no una excepción', () async {
      final result = await repository.updateRelation(
        'no-existe',
        kind: RelationKind.cites,
      );

      expect(result.isLeft(), isTrue);
    });
  });

  group('«no era»', () {
    test('lo borra y lo recuerda, sin importar el sentido', () async {
      final row = await aiRelation(from: 'b', to: 'a');

      final result = await repository.rejectAiRelation(row.id);

      expect(result.isRight(), isTrue);
      expect(await db.select(db.relations).get(), isEmpty);
      final memory = await db.select(db.aiRejections).getSingle();
      expect(memory.kind, AiRejectionKind.relation);
      expect(memory.itemId, 'a');
      expect(memory.otherItemId, 'b');
      expect(memory.subjectId, row.id);
      expect(
        await runs.isRelationRejected(
          fromItemId: 'a',
          toItemId: 'b',
          kind: RelationKind.relatedTo,
        ),
        right<Failure, bool>(true),
      );
    });

    test('y la IA ya no lo puede volver a crear, en ningún sentido', () async {
      final row = await aiRelation();
      await repository.rejectAiRelation(row.id);
      final run = await startRun();

      final again = await repository.createRelation(
        fromItemId: 'b',
        toItemId: 'a',
        kind: RelationKind.relatedTo,
        ai: AiProvenance(runId: run),
      );

      expect(again.getLeft().toNullable(), isA<ValidationFailure>());
      expect(await db.select(db.relations).get(), isEmpty);
    });

    test('pero la persona sí, y la IA con otro tipo también', () async {
      final row = await aiRelation();
      await repository.rejectAiRelation(row.id);
      final run = await startRun();

      final otherKind = await repository.createRelation(
        fromItemId: 'a',
        toItemId: 'b',
        kind: RelationKind.cites,
        ai: AiProvenance(runId: run),
      );
      final byHand = await repository.createRelation(
        fromItemId: 'a',
        toItemId: 'b',
        kind: RelationKind.relatedTo,
      );

      expect(otherKind.isRight(), isTrue);
      expect(byHand.isRight(), isTrue);
    });

    test('uno de la persona no se rechaza: se borra', () async {
      await repository.createRelation(
        fromItemId: 'a',
        toItemId: 'b',
        kind: RelationKind.cites,
      );

      final result = await repository.rejectAiRelation(
        (await onlyRelation()).id,
      );

      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      expect(await db.select(db.relations).get(), hasLength(1));
      expect(await db.select(db.aiRejections).get(), isEmpty);
    });

    test('deshacerlo lo devuelve tal cual y lo olvida', () async {
      final row = await aiRelation();
      final receipt = (await repository.rejectAiRelation(
        row.id,
      )).getOrElse((f) => fail('$f'));

      final restored = await repository.restoreRejectedRelation(receipt);

      expect(restored.isRight(), isTrue);
      expect(await onlyRelation(), row);
      expect(await db.select(db.aiRejections).get(), isEmpty);
    });
  });

  group('las propiedades', () {
    late String tema;

    setUp(() async => tema = await temaDefinitionId(db));

    test('la IA las pone con su pasada, y sin pasada no se puede', () async {
      final run = await startRun();

      final withoutRun = await repository.assignProperty(
        itemId: 'a',
        definitionId: tema,
        value: 'Roma',
        origin: ItemPropertyOrigin.ai,
      );
      final withRun = await repository.assignProperty(
        itemId: 'a',
        definitionId: tema,
        value: 'Roma',
        origin: ItemPropertyOrigin.ai,
        aiRunId: run,
      );

      expect(withoutRun.isLeft(), isTrue);
      expect(withRun.isRight(), isTrue);
      final row = await db.select(db.itemPropertyValues).getSingle();
      expect(row.origin, ItemPropertyOrigin.ai);
      expect(row.aiRunId, run);
    });

    test('la IA nunca pisa una que puso la persona', () async {
      await repository.assignProperty(
        itemId: 'a',
        definitionId: tema,
        value: 'Roma',
      );
      final run = await startRun();

      await repository.assignProperty(
        itemId: 'a',
        definitionId: tema,
        value: 'roma',
        origin: ItemPropertyOrigin.ai,
        aiRunId: run,
      );

      final row = await db.select(db.itemPropertyValues).getSingle();
      expect(row.origin, ItemPropertyOrigin.manual);
      expect(row.aiRunId, isNull);
    });

    test('guardar el elemento no le borra la pasada a una de la IA', () async {
      final run = await startRun();
      await db
          .into(db.propertyDefinitions)
          .insert(
            PropertyDefinitionsCompanion.insert(
              id: 'region',
              name: 'Región',
              createdAt: now,
            ),
          );
      for (final (definition, value) in [(tema, 'Roma'), ('region', 'Lacio')]) {
        await repository.assignProperty(
          itemId: 'a',
          definitionId: definition,
          value: value,
          origin: ItemPropertyOrigin.ai,
          aiRunId: run,
        );
      }
      final library = LibraryRepositoryImpl(
        database: db,
        telemetry: _MockTelemetryService(),
        files: InMemoryFileStore(),
      );
      final item = (await library.findById('a')).getOrElse((f) => fail('$f'));

      await library.save(item!.copyWith(title: 'Otro título'));

      final rows = await db.select(db.itemPropertyValues).get();
      expect(rows, hasLength(2));
      for (final row in rows) {
        expect(row.origin, ItemPropertyOrigin.ai);
        expect(row.aiRunId, run);
      }
    });

    test('«no era» la saca, la recuerda y la IA no la vuelve a poner — '
        'la persona sí', () async {
      final run = await startRun();
      await repository.assignProperty(
        itemId: 'a',
        definitionId: tema,
        value: 'Roma',
        origin: ItemPropertyOrigin.ai,
        aiRunId: run,
      );
      final valueId =
          (await db.select(db.itemPropertyValues).getSingle()).propertyValueId;

      final receipt = (await repository.rejectAiProperty(
        itemId: 'a',
        propertyValueId: valueId,
      )).getOrElse((f) => fail('$f'));

      expect(await db.select(db.itemPropertyValues).get(), isEmpty);
      expect(
        await runs.isPropertyRejected(
          itemId: 'a',
          definitionName: 'tema',
          value: 'ROMA',
        ),
        right<Failure, bool>(true),
      );
      final again = await repository.assignProperty(
        itemId: 'a',
        definitionId: tema,
        value: 'Roma',
        origin: ItemPropertyOrigin.ai,
        aiRunId: run,
      );
      expect(again.isLeft(), isTrue);

      await repository.restoreRejectedProperty(receipt);
      final back = await db.select(db.itemPropertyValues).getSingle();
      expect(back.origin, ItemPropertyOrigin.ai);
      expect(back.aiRunId, run);
      expect(await db.select(db.aiRejections).get(), isEmpty);
    });
  });
}
