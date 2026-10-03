import 'package:drift/native.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/ai_organize/data/repositories/ai_run_repository_impl.dart';
import 'package:sinapsis/features/duplicates/data/usecases/merge_duplicate_items_usecase_impl.dart';
import 'package:sinapsis/features/flashcards/data/repositories/flashcard_repository_impl.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/organize/data/repositories/organize_repository_impl.dart';
import 'package:sinapsis/features/suggestions/data/repositories/suggestion_repository_impl.dart';

import 'fake_id_generator.dart';
import 'in_memory_file_store.dart';

class _MockTelemetryService extends Mock implements TelemetryService {}

/// La bóveda de las pruebas de la IA que organiza sola (F27): SQLite real en
/// memoria con los repositorios reales —las pasadas, los vínculos, las
/// tarjetas, las sugerencias—. Lo único falso en esas pruebas son los
/// modelos: el de lenguaje y el de embeddings.
class AiOrganizeHarness {
  final db = AppDatabase(NativeDatabase.memory());
  final ids = FakeIdGenerator();
  final files = InMemoryFileStore();
  final TelemetryService telemetry = _MockTelemetryService();

  /// La hora de la bóveda; se puede mover.
  DateTime now = DateTime(2026, 10, 2, 10);
  DateTime clock() => now;

  late final library = LibraryRepositoryImpl(
    database: db,
    telemetry: telemetry,
    files: files,
    ids: ids,
    clock: clock,
  );

  late final organize = OrganizeRepositoryImpl(
    database: db,
    telemetry: telemetry,
    ids: ids,
    clock: clock,
  );

  late final flashcards = FlashcardRepositoryImpl(
    database: db,
    telemetry: telemetry,
    ids: ids,
    clock: clock,
  );

  late final runs = AiRunRepositoryImpl(
    database: db,
    telemetry: telemetry,
    ids: ids,
    clock: clock,
  );

  late final suggestions = SuggestionRepositoryImpl(
    database: db,
    telemetry: telemetry,
    organize: organize,
    merge: MergeDuplicateItemsUseCaseImpl(
      database: db,
      library: library,
      ids: ids,
      clock: clock,
      telemetry: telemetry,
    ),
    ids: ids,
    clock: clock,
  );

  /// Guarda una fuente lista, con [content] como su texto.
  Future<KnowledgeItem> source(
    String id, {
    required String title,
    required String content,
    SourceKind kind = SourceKind.webPage,
    DateTime? createdAt,
  }) => _save(
    id,
    title: title,
    content: content,
    kind: kind,
    renditionKind: RenditionKind.plainText,
    createdAt: createdAt,
  );

  /// Guarda una nota con [content] como su texto.
  Future<KnowledgeItem> note(
    String id, {
    required String title,
    required String content,
    DateTime? createdAt,
  }) => _save(
    id,
    title: title,
    content: content,
    kind: SourceKind.manualNote,
    renditionKind: RenditionKind.markdown,
    createdAt: createdAt,
  );

  Future<KnowledgeItem> _save(
    String id, {
    required String title,
    required String content,
    required SourceKind kind,
    required RenditionKind renditionKind,
    DateTime? createdAt,
  }) async {
    final at = createdAt ?? now;
    final item = KnowledgeItem(
      id: id,
      title: title,
      source: Source(id: 'src-$id', kind: kind, capturedAt: at),
      processingState: ProcessingState.ready,
      createdAt: at,
      updatedAt: at,
      renditions: [
        Rendition.text(
          id: 'rend-$id',
          itemId: id,
          kind: renditionKind,
          content: content,
          isPrimary: true,
          createdAt: at,
        ),
      ],
    );
    return (await library.save(
      item,
    )).getOrElse((f) => throw StateError('No se pudo guardar $id: $f'));
  }

  /// El elemento [id] como está ahora en la base.
  Future<KnowledgeItem> reload(String id) async =>
      (await library.findById(id)).getOrElse((f) => throw StateError('$f'))!;

  /// Abre una pasada de la IA sobre [itemId].
  Future<String> startRun(String itemId) async =>
      (await runs.startRun(itemId)).getOrElse((f) => throw StateError('$f'));

  Future<void> close() => db.close();
}
