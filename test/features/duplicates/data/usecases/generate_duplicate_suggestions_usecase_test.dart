import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/duplicate_match_kind.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/domain/services/dedup_fingerprint.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/duplicates/data/services/duplicate_candidate_selector_impl.dart';
import 'package:sinapsis/features/duplicates/data/usecases/generate_duplicate_suggestions_usecase.dart';
import 'package:sinapsis/features/duplicates/data/usecases/merge_duplicate_items_usecase_impl.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/organize/data/repositories/organize_repository_impl.dart';
import 'package:sinapsis/features/suggestions/data/repositories/suggestion_repository_impl.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';
import '../../../../support/item_rows.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Contra SQLite real, en memoria, con `LibraryRepositoryImpl` y
/// `SuggestionRepositoryImpl` reales: el fingerprint que este generador
/// persiste y la sugerencia que crea dependen de datos de verdad, no de
/// un doble.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late SuggestionRepositoryImpl suggestions;
  late GenerateDuplicateSuggestionsUseCase generator;
  late FakeIdGenerator ids;

  final now = DateTime(2026, 9, 18, 10);
  var counter = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    ids = FakeIdGenerator();
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
    );
    final organize = OrganizeRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      ids: ids,
      clock: () => now,
    );
    final merge = MergeDuplicateItemsUseCaseImpl(
      database: db,
      library: library,
      ids: ids,
      clock: () => now,
      telemetry: MockTelemetryService(),
    );
    suggestions = SuggestionRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      organize: organize,
      merge: merge,
      ids: ids,
      clock: () => now,
    );
    generator = GenerateDuplicateSuggestionsUseCase(
      database: db,
      selector: DuplicateCandidateSelectorImpl(database: db),
      suggestions: suggestions,
      telemetry: MockTelemetryService(),
    );
    counter = 0;
  });

  tearDown(() => db.close());

  Future<KnowledgeItem> seedItem({
    required String title,
    required String text,
  }) async {
    final n = counter++;
    final itemId = 'item-$n';
    final item = KnowledgeItem(
      id: itemId,
      title: title,
      source: Source(
        id: 'src-$n',
        kind: SourceKind.webPage,
        capturedAt: now,
        url: 'https://ejemplo.org/$n',
      ),
      processingState: ProcessingState.ready,
      createdAt: now,
      updatedAt: now,
      renditions: [
        Rendition.text(
          id: 'rend-$n',
          itemId: itemId,
          kind: RenditionKind.plainText,
          content: text,
          isPrimary: true,
          createdAt: now,
        ),
      ],
    );
    final result = await library.save(item);
    return result.getRight().toNullable()!;
  }

  test('sin ninguna coincidencia, no genera nada', () async {
    final item = await seedItem(
      title: 'Solo',
      text: 'un texto sin relación con nada más en esta bóveda',
    );

    await generator.generate(item);

    final pending = await suggestions.watchPendingSuggestions(item.id).first;
    expect(pending, isEmpty);
  });

  test('persiste el dedupHash/simhash del elemento, aunque no haya '
      'ninguna coincidencia', () async {
    final item = await seedItem(title: 'Solo', text: 'cualquier texto');

    await generator.generate(item);

    final row = await (db.select(
      db.knowledgeSources,
    )..where((s) => s.itemId.equals(item.id))).getSingle();
    expect(row.dedupHash, isNotNull);
    expect(row.simhash, isNotNull);
  });

  test('una coincidencia exacta genera una sugerencia pendiente', () async {
    final existing = await seedItem(
      title: 'Ya existente',
      text: 'el mismo texto exacto',
    );
    final incoming = await seedItem(
      title: 'Recién llegado',
      text: 'el mismo texto exacto',
    );
    // El fingerprint de `existing` tiene que estar persistido para que
    // haya algo con qué comparar — lo hace el propio generador, la
    // primera vez que le toca.
    await generator.generate(existing);

    await generator.generate(incoming);

    final pending = await suggestions
        .watchPendingSuggestions(incoming.id)
        .first;
    expect(pending, hasLength(1));
    final suggestion = pending.single as DuplicateSuggestionEntry;
    expect(suggestion.duplicateItemId, existing.id);
    expect(suggestion.duplicateItemTitle, 'Ya existente');
    expect(suggestion.matchKind, DuplicateMatchKind.exact);
  });

  test(
    'una coincidencia cercana también genera una sugerencia pendiente',
    () async {
      const incomingText = 'un texto cualquiera para probar la cercanía';
      final incoming = await seedItem(
        title: 'Recién llegado',
        text: incomingText,
      );
      final existing = await seedItem(title: 'Ya existente', text: 'otro');

      // Un simhash a 2 bits del que le va a tocar calcular al generador
      // para `incoming` —distancia de Hamming 2, dentro del umbral por
      // defecto (<= 3)—, con un `dedupHash` distinto para que cuente como
      // casi-duplicado, no exacto.
      final incomingSimhash = simhashOf(normalizeForDedup(incomingText));
      final nearSimhash =
          (BigInt.parse(incomingSimhash, radix: 16) ^ BigInt.from(3))
              .toRadixString(16)
              .padLeft(16, '0');
      await (db.update(
        db.knowledgeSources,
      )..where((s) => s.itemId.equals(existing.id))).write(
        KnowledgeSourcesCompanion(
          dedupHash: const Value('hash-no-relacionado'),
          simhash: Value(nearSimhash),
        ),
      );

      await generator.generate(incoming);

      final pending = await suggestions
          .watchPendingSuggestions(incoming.id)
          .first;
      final suggestion = pending.single as DuplicateSuggestionEntry;
      expect(suggestion.duplicateItemId, existing.id);
      expect(suggestion.matchKind, DuplicateMatchKind.near);
    },
  );

  test(
    'no genera una segunda si ya hay una pendiente para el mismo par',
    () async {
      final existing = await seedItem(
        title: 'Ya existente',
        text: 'texto repetido',
      );
      final incoming = await seedItem(
        title: 'Recién llegado',
        text: 'texto repetido',
      );
      await generator.generate(existing);
      await generator.generate(incoming);

      // Se vuelve a llamar para el mismo par —simula una nota editada de
      // nuevo, D7— y no debería duplicar la sugerencia, sin importar desde
      // cuál de los dos lados se dispare.
      await generator.generate(incoming);
      await generator.generate(existing);

      final pendingForIncoming = await suggestions
          .watchPendingSuggestions(incoming.id)
          .first;
      final pendingForExisting = await suggestions
          .watchPendingSuggestions(existing.id)
          .first;
      expect(pendingForIncoming.length + pendingForExisting.length, 1);
    },
  );

  group('la papelera (F11)', () {
    test('no propone como duplicado algo que está en la papelera', () async {
      final existing = await seedItem(
        title: 'Ya existente',
        text: 'el mismo texto exacto',
      );
      final incoming = await seedItem(
        title: 'Recién llegado',
        text: 'el mismo texto exacto',
      );
      await generator.generate(existing);
      await trashItemRows(db, existing.id);

      await generator.generate(incoming);

      expect(
        await suggestions.watchPendingSuggestions(incoming.id).first,
        isEmpty,
      );
      expect(await db.select(db.suggestions).get(), isEmpty);
    });
  });
}
