import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/library_view_mode.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/data/repositories/saved_view_repository_impl.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';

import '../../../../support/fake_id_generator.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Contra SQLite real, en memoria: lo que hay que verificar es que el filtro
/// y el orden de una vista sobreviven a una vuelta completa por la base
/// —codificados como JSON—, y que el orden entre las vistas guardadas se
/// mantiene y se puede cambiar.
void main() {
  late AppDatabase db;
  late SavedViewRepositoryImpl repository;
  late FakeIdGenerator ids;
  var now = DateTime(2026, 9, 24, 10);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    ids = FakeIdGenerator();
    now = DateTime(2026, 9, 24, 10);
    repository = SavedViewRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      ids: ids,
      clock: () => now,
    );
  });

  tearDown(() => db.close());

  group('create', () {
    test(
      'guarda el filtro, el orden y el modo, y los devuelve iguales',
      () async {
        const query = LibraryQuery(
          searchText: 'paradigma',
          sourceKinds: {SourceKind.webPage, SourceKind.youtube},
          processingStates: {ProcessingState.ready},
          sortBy: LibrarySort.publishedAt,
          descending: false,
        );

        final view = await repository.create(
          name: 'Videos de este mes',
          query: query,
          viewMode: LibraryViewMode.kanban,
        );

        expect(view.name, 'Videos de este mes');
        expect(view.viewMode, LibraryViewMode.kanban);
        expect(view.pinned, isFalse);
        expect(view.createdAt, now);

        final all = await repository.watchAll().first;
        expect(all, hasLength(1));
        expect(all.single.query, query);
      },
    );

    test(
      'no guarda ids, límite ni página: son de la sesión, no del filtro',
      () async {
        final view = await repository.create(
          name: 'Selección',
          query: const LibraryQuery(ids: {'a', 'b'}, limit: 20, offset: 40),
          viewMode: LibraryViewMode.list,
        );

        final saved = (await repository.watchAll().first).single;
        expect(saved.query.ids, isNull);
        expect(saved.query.limit, isNull);
        expect(saved.query.offset, 0);
        expect(view.id, isNotEmpty);
      },
    );

    test('cada vista nueva queda al final del orden', () async {
      await repository.create(
        name: 'Uno',
        query: const LibraryQuery(),
        viewMode: LibraryViewMode.list,
      );
      await repository.create(
        name: 'Dos',
        query: const LibraryQuery(),
        viewMode: LibraryViewMode.list,
      );

      final all = await repository.watchAll().first;
      expect(all.map((v) => v.name), ['Uno', 'Dos']);
    });
  });

  group('rename, setPinned, reorder y delete', () {
    test('cada una cambia solo lo suyo', () async {
      final a = await repository.create(
        name: 'A',
        query: const LibraryQuery(),
        viewMode: LibraryViewMode.list,
      );
      final b = await repository.create(
        name: 'B',
        query: const LibraryQuery(),
        viewMode: LibraryViewMode.list,
      );

      await repository.rename(a.id, 'A renombrada');
      await repository.setPinned(b.id, pinned: true);

      final afterRename = await repository.watchAll().first;
      expect(afterRename.firstWhere((v) => v.id == a.id).name, 'A renombrada');
      expect(afterRename.firstWhere((v) => v.id == b.id).pinned, isTrue);
      expect(afterRename.firstWhere((v) => v.id == a.id).pinned, isFalse);

      await repository.reorder([b.id, a.id]);
      final afterReorder = await repository.watchAll().first;
      expect(afterReorder.map((v) => v.id), [b.id, a.id]);

      await repository.delete(a.id);
      final afterDelete = await repository.watchAll().first;
      expect(afterDelete.map((v) => v.id), [b.id]);
    });
  });
}
