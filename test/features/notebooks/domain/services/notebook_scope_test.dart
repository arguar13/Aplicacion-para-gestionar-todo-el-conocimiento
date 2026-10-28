import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/inbox_status.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/notebooks/domain/services/notebook_scope.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_query.dart';

/// Qué documentos procesados pide la vista guardada de un cuaderno por
/// consulta (F41, paso 5).
void main() {
  group('processedQueryForView', () {
    test('lo que un procesado también tiene pasa tal cual', () {
      final query = processedQueryForView(
        const LibraryQuery(
          searchText: 'senado',
          spaceId: 'roma',
          tagIds: {'imperio'},
          propertyValueIds: {'siglo-i'},
          sourceKinds: {SourceKind.document},
          ids: {'a', 'b'},
        ),
      );

      expect(
        query,
        const ProcessedQuery(
          searchText: 'senado',
          spaceId: 'roma',
          tagIds: {'imperio'},
          propertyValueIds: {'siglo-i'},
          sourceKinds: {SourceKind.document},
          ids: {'a', 'b'},
          sortBy: ProcessedSort.createdAt,
        ),
      );
    });

    test('un procesado siempre está listo: pedir lo listo no recorta, pedir '
        'lo pendiente no trae nada', () {
      expect(
        processedQueryForView(
          const LibraryQuery(
            processingStates: {ProcessingState.ready, ProcessingState.failed},
          ),
        ).ids,
        isNull,
      );
      expect(
        processedQueryForView(
          const LibraryQuery(
            processingStates: {ProcessingState.pending},
            ids: {'a'},
          ),
        ).ids,
        isEmpty,
      );
    });

    test('lo decidido en la Bandeja es de las fuentes: no trae ningún '
        'procesado', () {
      expect(
        processedQueryForView(
          const LibraryQuery(inboxStatuses: {InboxStatus.triaged}),
        ).ids,
        isEmpty,
      );
    });

    test('el orden se traduce al más parecido, con su sentido', () {
      ProcessedSort sortOf(LibrarySort sort) =>
          processedQueryForView(LibraryQuery(sortBy: sort)).sortBy;

      expect(sortOf(LibrarySort.capturedAt), ProcessedSort.createdAt);
      expect(sortOf(LibrarySort.publishedAt), ProcessedSort.createdAt);
      expect(sortOf(LibrarySort.updatedAt), ProcessedSort.updatedAt);
      expect(sortOf(LibrarySort.relevance), ProcessedSort.updatedAt);
      expect(sortOf(LibrarySort.title), ProcessedSort.title);
      expect(
        processedQueryForView(
          const LibraryQuery(sortBy: LibrarySort.title, descending: false),
        ).descending,
        isFalse,
      );
    });

    test('la página se ignora: un cuaderno es todo lo que la vista trae', () {
      final query = processedQueryForView(
        const LibraryQuery(limit: 10, offset: 20),
      );

      expect(query.limit, isNull);
      expect(query.offset, 0);
    });
  });

  test('un cuaderno a mano pide sus procesados por id', () {
    expect(
      processedQueryForMembers({'a', 'b'}),
      const ProcessedQuery(ids: {'a', 'b'}),
    );
  });
}
