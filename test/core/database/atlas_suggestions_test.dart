import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/atlas_suggestions.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/domain/entities/suggestion_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/core/error/failures.dart';

import '../../support/ai_organize_harness.dart';
import '../../support/atlas_topics.dart';

/// Las sugerencias del Atlas de la IA (F27): dónde va un tema suelto y la
/// madurez de una nota viva. Se leen, se aceptan y se deshacen por los
/// repositorios de siempre.
void main() {
  late AiOrganizeHarness vault;
  late AtlasTopics topics;
  late String temaId;
  late String historia;
  late String roma;

  setUp(() async {
    vault = AiOrganizeHarness();
    topics = AtlasTopics(vault.db);
    temaId = await temaDefinitionId(vault.db);
    historia = await topics.add('Historia antigua');
    await topics.add('Grecia', parentId: historia);
    roma = await topics.add('Roma');
    await vault.source('a', title: 'Las legiones', content: 'Roma.');
  });

  tearDown(() => vault.close());

  Future<String> placement({
    String status = 'pending',
    String? aiRunId,
    String? valueId,
    String? parentId,
  }) async {
    final id = 's-${vault.ids.next()}';
    await vault.db
        .into(vault.db.suggestions)
        .insert(
          SuggestionsCompanion.insert(
            id: id,
            kind: SuggestionKind.topicParent,
            targetItemId: 'a',
            payloadJson: encodeTopicParentPayload(
              definitionId: temaId,
              valueId: valueId ?? roma,
              valueName: 'Roma',
              parentId: parentId ?? historia,
              parentName: 'Historia antigua',
              aiRunId: aiRunId,
            ),
            status: Value(SuggestionStatus.values.byName(status)),
            createdAt: vault.now,
          ),
        );
    return id;
  }

  group('el lugar de un tema en el árbol', () {
    test('se lee con sus nombres y, aceptado, cuelga el tema del padre y le '
        'recalcula el nivel', () async {
      final id = await placement();

      final pending =
          (await vault.suggestions.watchPendingSuggestions('a').first).single
              as TopicParentSuggestion;
      expect(
        (pending.valueName, pending.parentName, pending.aiRunId),
        ('Roma', 'Historia antigua', null),
      );

      expect((await vault.suggestions.accept(id)).isRight(), isTrue);

      final row = await topics.row(roma);
      expect((row.parentId, row.depth), (historia, 1));
      expect(
        await vault.suggestions.watchPendingSuggestions('a').first,
        isEmpty,
      );
    });

    test('no mueve un tema que la persona ya ubicó: lo dice y la propuesta '
        'sigue pendiente', () async {
      final id = await placement();
      const grecia = 't-Grecia';
      await (vault.db.update(vault.db.propertyValues)
            ..where((v) => v.id.equals(roma)))
          .write(const PropertyValuesCompanion(parentId: Value(grecia)));

      final result = await vault.suggestions.accept(id);

      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      expect(await topics.parentOf(roma), grecia);
      expect(
        await vault.suggestions.watchPendingSuggestions('a').first,
        hasLength(1),
      );
    });

    test('nunca deja un ciclo: un padre que es su propio subtema se niega', () {
      // «Historia antigua» bajo «Grecia», que ya cuelga de ella.
      return vault.db.transaction(() async {
        final result = await placeTopicValue(
          vault.db,
          valueId: historia,
          parentId: 't-Grecia',
        );
        expect(result.getLeft().toNullable(), isA<ValidationFailure>());
        expect(await topics.parentOf(historia), isNull);
      });
    });

    test('deshacer la pasada devuelve a la raíz lo que la IA ubicó sola, y '
        'deja lo que la persona movió después', () async {
      final run = await vault.startRun('a');
      final roman = await placement(status: 'accepted', aiRunId: run);
      final egipto = await topics.add('Egipto');
      final egyptian = await placement(
        status: 'accepted',
        aiRunId: run,
        valueId: egipto,
      );
      await vault.db.transaction(() async {
        await placeTopicValue(vault.db, valueId: roma, parentId: historia);
        await placeTopicValue(vault.db, valueId: egipto, parentId: historia);
      });
      // La persona se llevó «Egipto» a otro lado: ya es suyo.
      await (vault.db.update(vault.db.propertyValues)
            ..where((v) => v.id.equals(egipto)))
          .write(const PropertyValuesCompanion(parentId: Value('t-Grecia')));

      expect((await vault.runs.undoRun(run)).isRight(), isTrue);

      expect(await topics.parentOf(roma), isNull);
      expect((await topics.row(roma)).depth, 0);
      expect(await topics.parentOf(egipto), 't-Grecia');
      for (final id in [roman, egyptian]) {
        final row = await (vault.db.select(
          vault.db.suggestions,
        )..where((s) => s.id.equals(id))).getSingle();
        expect(row.status, SuggestionStatus.rejected, reason: id);
      }
    });

    test('«no era» una sola ubicación: vuelve a la raíz y no se puede '
        'deshacer una propuesta que nadie aplicó', () async {
      final run = await vault.startRun('a');
      final applied = await placement(status: 'accepted', aiRunId: run);
      final proposed = await placement(valueId: await topics.add('Egipto'));
      await vault.db.transaction(
        () => placeTopicValue(vault.db, valueId: roma, parentId: historia),
      );

      final undone = await vault.db.transaction(
        () => undoAiTopicPlacement(vault.db, applied),
      );
      final notApplied = await vault.db.transaction(
        () => undoAiTopicPlacement(vault.db, proposed),
      );

      expect(undone.getRight().toNullable(), isTrue);
      expect(await topics.parentOf(roma), isNull);
      expect(notApplied.getLeft().toNullable(), isA<ValidationFailure>());
    });

    test(
      'lo pendiente va a «Para revisar»; lo que la IA ya aplicó, no',
      () async {
        await placement();
        await placement(status: 'accepted', aiRunId: 'r');
        expect(await vault.suggestions.watchPendingReviewCount().first, 1);
      },
    );

    test('lo que la IA ya decidió sobre un tema se encuentra, en cualquier '
        'estado', () async {
      await placement(status: 'rejected');
      await placement(status: 'accepted', aiRunId: 'r');

      final about = await topicParentSuggestionsAbout(vault.db, roma);

      expect(about.map((s) => s.status), [
        SuggestionStatus.rejected,
        SuggestionStatus.accepted,
      ]);
      expect(await topicParentSuggestionsAbout(vault.db, historia), isEmpty);
    });
  });

  group('la madurez de una nota viva', () {
    Future<String> maturity(NoteMaturity from, NoteMaturity to) async {
      final id = 's-${vault.ids.next()}';
      await vault.db
          .into(vault.db.suggestions)
          .insert(
            SuggestionsCompanion.insert(
              id: id,
              kind: SuggestionKind.maturity,
              targetItemId: 'nota',
              payloadJson: encodeMaturityPayload(from: from, to: to),
              createdAt: vault.now,
            ),
          );
      return id;
    }

    test('se lee de cuál a cuál y, aceptada, la sube', () async {
      await vault.note('nota', title: 'Roma', content: 'Roma.');
      final id = await maturity(NoteMaturity.seed, NoteMaturity.developing);

      final pending =
          (await vault.suggestions.watchPendingSuggestions('nota').first).single
              as MaturitySuggestion;
      expect(
        (pending.from, pending.to),
        (NoteMaturity.seed, NoteMaturity.developing),
      );

      expect((await vault.suggestions.accept(id)).isRight(), isTrue);
      expect(await topics.maturityOf('nota'), NoteMaturity.developing);
    });

    test('descartarla no toca la nota', () async {
      await vault.note('nota', title: 'Roma', content: 'Roma.');
      final id = await maturity(NoteMaturity.seed, NoteMaturity.developing);

      await vault.suggestions.reject(id);

      expect(await topics.maturityOf('nota'), NoteMaturity.seed);
    });
  });
}
